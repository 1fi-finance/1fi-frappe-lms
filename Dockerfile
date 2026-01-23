# Frappe Lending - Production Dockerfile
# Based on Frappe version-15 with PostgreSQL support

ARG PYTHON_VERSION=3.11
ARG NODE_VERSION=18

# =============================================================================
# Stage 1: Base image with system dependencies
# =============================================================================
FROM python:${PYTHON_VERSION}-slim-bookworm AS base

ARG NODE_VERSION

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    git \
    curl \
    wget \
    # PostgreSQL client
    libpq-dev \
    postgresql-client \
    # Redis tools
    redis-tools \
    # wkhtmltopdf dependencies
    fontconfig \
    libfontconfig1 \
    libfreetype6 \
    libjpeg62-turbo \
    libpng16-16 \
    libx11-6 \
    libxcb1 \
    libxext6 \
    libxrender1 \
    xfonts-75dpi \
    xfonts-base \
    # Additional dependencies
    libssl-dev \
    libffi-dev \
    libjpeg-dev \
    zlib1g-dev \
    libxml2-dev \
    libxslt1-dev \
    # Supervisor for process management
    supervisor \
    # Nginx (optional, for production)
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Install wkhtmltopdf (required for PDF generation)
RUN wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && dpkg -i wkhtmltox_0.12.6.1-3.bookworm_amd64.deb || apt-get install -f -y \
    && rm wkhtmltox_0.12.6.1-3.bookworm_amd64.deb

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn

# Create frappe user
RUN useradd -ms /bin/bash frappe
ENV HOME=/home/frappe
WORKDIR /home/frappe

# =============================================================================
# Stage 2: Frappe Bench setup
# =============================================================================
FROM base AS bench-setup

USER frappe

# Install Frappe Bench
RUN pip install --user frappe-bench

ENV PATH="${HOME}/.local/bin:${PATH}"

# Initialize bench with Frappe version-15
ARG FRAPPE_BRANCH=version-15
RUN bench init \
    --frappe-branch ${FRAPPE_BRANCH} \
    --skip-redis-config-generation \
    --skip-assets \
    --python python3.11 \
    frappe-bench

WORKDIR /home/frappe/frappe-bench

# =============================================================================
# Stage 3: App installation
# =============================================================================
FROM bench-setup AS app-install

ARG ERPNEXT_BRANCH=version-15
ARG PAYMENTS_BRANCH=version-15

# Get ERPNext (required dependency)
RUN bench get-app --branch ${ERPNEXT_BRANCH} erpnext

# Get Payments app (optional but recommended)
RUN bench get-app --branch ${PAYMENTS_BRANCH} payments || true

# Copy lending app
COPY --chown=frappe:frappe . /home/frappe/frappe-bench/apps/lending

# Install app dependencies
RUN bench setup requirements --dev

# Build assets
RUN bench build --production

# =============================================================================
# Stage 4: Production image
# =============================================================================
FROM base AS production

USER frappe
WORKDIR /home/frappe

# Copy bench from app-install stage
COPY --from=app-install --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench
COPY --from=app-install --chown=frappe:frappe /home/frappe/.local /home/frappe/.local

ENV PATH="${HOME}/.local/bin:${PATH}"
WORKDIR /home/frappe/frappe-bench

# Copy configuration files
COPY --chown=frappe:frappe docker/supervisord.conf /etc/supervisor/conf.d/frappe.conf
COPY --chown=frappe:frappe docker/entrypoint.sh /entrypoint.sh

USER root
RUN chmod +x /entrypoint.sh

USER frappe

# Expose ports
# 8000 - Frappe web
# 9000 - SocketIO
# 8001 - Gunicorn workers
EXPOSE 8000 9000 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/api/method/ping || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["prod"]
