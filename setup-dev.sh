#!/bin/bash

# Frappe Lending Development Setup Script
# Run this in WSL Ubuntu: bash setup-dev.sh

set -e

echo "============================================"
echo "  Frappe Lending Development Setup"
echo "============================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Configuration
DB_ROOT_PASSWORD="admin123"
ADMIN_PASSWORD="admin"
SITE_NAME="lending.localhost"
BENCH_DIR="$HOME/frappe-bench"

echo ""
echo "Configuration:"
echo "  - Site: $SITE_NAME"
echo "  - Bench directory: $BENCH_DIR"
echo "  - DB Root Password: $DB_ROOT_PASSWORD"
echo "  - Admin Password: $ADMIN_PASSWORD"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Step 1: Install system dependencies
log "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    git \
    python3-dev \
    python3-pip \
    python3-venv \
    redis-server \
    mariadb-server \
    mariadb-client \
    libmariadb-dev \
    libffi-dev \
    libssl-dev \
    wkhtmltopdf \
    xvfb \
    libfontconfig \
    curl

# Step 2: Install Node.js 18 if not present or wrong version
NODE_VERSION=$(node --version 2>/dev/null | cut -d'v' -f2 | cut -d'.' -f1 || echo "0")
if [ "$NODE_VERSION" -lt 18 ]; then
    log "Installing Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# Install yarn
log "Installing Yarn..."
sudo npm install -g yarn

# Step 3: Start services
log "Starting Redis..."
sudo service redis-server start

log "Starting MariaDB..."
sudo service mariadb start

# Step 4: Configure MariaDB
log "Configuring MariaDB..."
sudo mysql -u root <<EOF || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

# Test MariaDB connection
if mysql -u root -p"${DB_ROOT_PASSWORD}" -e "SELECT 1" &>/dev/null; then
    log "MariaDB configured successfully!"
else
    warn "MariaDB may need manual configuration. Trying without password..."
fi

# Step 5: Install bench using pipx
log "Installing Frappe Bench..."
apt-get install -y pipx
pipx install frappe-bench
pipx ensurepath

# Add to PATH
export PATH="$HOME/.local/bin:$PATH"
source ~/.bashrc 2>/dev/null || true

# Step 6: Initialize bench
if [ -d "$BENCH_DIR" ]; then
    warn "Bench directory exists. Skipping init..."
    cd "$BENCH_DIR"
else
    log "Initializing Frappe Bench..."
    bench init --frappe-branch version-15 "$BENCH_DIR"
    cd "$BENCH_DIR"
fi

# Step 7: Create site
if [ -d "sites/$SITE_NAME" ]; then
    warn "Site $SITE_NAME already exists. Skipping..."
else
    log "Creating site: $SITE_NAME..."
    bench new-site "$SITE_NAME" \
        --admin-password "$ADMIN_PASSWORD" \
        --db-root-password "$DB_ROOT_PASSWORD" \
        --no-mariadb-socket
fi

# Set as default site
bench use "$SITE_NAME"

# Step 8: Get and install ERPNext
if [ -d "apps/erpnext" ]; then
    warn "ERPNext already installed. Skipping..."
else
    log "Getting ERPNext..."
    bench get-app erpnext --branch version-15
    log "Installing ERPNext..."
    bench --site "$SITE_NAME" install-app erpnext
fi

# Step 9: Get and install Lending
if [ -d "apps/lending" ]; then
    warn "Lending app already installed. Skipping..."
else
    log "Getting Lending app..."
    bench get-app lending --branch develop
    log "Installing Lending app..."
    bench --site "$SITE_NAME" install-app lending
fi

# Step 10: Build assets
log "Building assets..."
bench build

echo ""
echo "============================================"
echo -e "${GREEN}  Setup Complete!${NC}"
echo "============================================"
echo ""
echo "To start the development server:"
echo "  cd $BENCH_DIR"
echo "  bench start"
echo ""
echo "Then open: http://localhost:8000"
echo "  Username: Administrator"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "To start services on next boot:"
echo "  sudo service redis-server start"
echo "  sudo service mariadb start"
echo ""

# Ask to start now
read -p "Start development server now? (y/n): " START_NOW
if [ "$START_NOW" = "y" ] || [ "$START_NOW" = "Y" ]; then
    bench start
fi
