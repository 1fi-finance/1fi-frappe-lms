#!/bin/bash
set -e

# Frappe Lending Entrypoint Script
# Handles site initialization, app installation, and service startup

cd /home/frappe/frappe-bench

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

wait_for_db() {
    log "Waiting for database to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if [ "$DB_TYPE" = "postgres" ]; then
            if pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "$DB_USER" > /dev/null 2>&1; then
                log "PostgreSQL is ready!"
                return 0
            fi
        else
            if mysqladmin ping -h "$DB_HOST" -P "${DB_PORT:-3306}" -u "$DB_USER" -p"$DB_PASSWORD" --silent > /dev/null 2>&1; then
                log "MariaDB is ready!"
                return 0
            fi
        fi
        log "Database not ready yet (attempt $attempt/$max_attempts)..."
        sleep 2
        attempt=$((attempt + 1))
    done

    log "ERROR: Database connection failed after $max_attempts attempts"
    exit 1
}

wait_for_redis() {
    log "Waiting for Redis to be ready..."
    local max_attempts=10
    local attempt=1
    local redis_host="${REDIS_CACHE_HOST:-redis}"
    local redis_port="${REDIS_CACHE_PORT:-6379}"

    log "Trying to connect to Redis at $redis_host:$redis_port"

    while [ $attempt -le $max_attempts ]; do
        # Use Python for portable TCP check (available in all Frappe images)
        if python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('$redis_host', $redis_port)); s.close(); print('OK')" 2>/dev/null; then
            log "Redis is ready at $redis_host:$redis_port!"
            return 0
        fi
        log "Redis not ready yet at $redis_host:$redis_port (attempt $attempt/$max_attempts)..."
        sleep 2
        attempt=$((attempt + 1))
    done

    # Don't fail - let Frappe handle Redis connection
    log "WARNING: Could not verify Redis connection at $redis_host:$redis_port, continuing anyway..."
    return 0
}

setup_common_site_config() {
    log "Setting up common site config..."

    # Determine DB configuration
    if [ -n "$DATABASE_URL" ]; then
        # Parse DATABASE_URL (format: postgres://user:pass@host:port/dbname)
        export DB_TYPE="postgres"
        DB_USER=$(echo "$DATABASE_URL" | sed -E 's|.*://([^:]+):.*|\1|')
        DB_PASSWORD=$(echo "$DATABASE_URL" | sed -E 's|.*://[^:]+:([^@]+)@.*|\1|')
        DB_HOST=$(echo "$DATABASE_URL" | sed -E 's|.*@([^:]+):.*|\1|')
        DB_PORT=$(echo "$DATABASE_URL" | sed -E 's|.*:([0-9]+)/.*|\1|')
        DB_NAME=$(echo "$DATABASE_URL" | sed -E 's|.*/([^?]+).*|\1|')
    fi

    # Create common_site_config.json
    cat > sites/common_site_config.json << EOF
{
    "db_host": "${DB_HOST:-db}",
    "db_port": ${DB_PORT:-5432},
    "db_type": "${DB_TYPE:-postgres}",
    "redis_cache": "redis://${REDIS_CACHE_HOST:-redis}:${REDIS_CACHE_PORT:-6379}/0",
    "redis_queue": "redis://${REDIS_QUEUE_HOST:-redis}:${REDIS_QUEUE_PORT:-6379}/1",
    "redis_socketio": "redis://${REDIS_SOCKETIO_HOST:-redis}:${REDIS_SOCKETIO_PORT:-6379}/2",
    "socketio_port": 9000,
    "webserver_port": 8000,
    "developer_mode": ${DEVELOPER_MODE:-0},
    "serve_default_site": true,
    "frappe_user": "frappe",
    "auto_update": false,
    "maintenance_mode": 0,
    "pause_scheduler": 0
}
EOF

    log "Common site config created"
}

create_site() {
    local site_name="${SITE_NAME:-lending.localhost}"

    if [ -d "sites/$site_name" ]; then
        log "Site $site_name already exists, skipping creation"
        return 0
    fi

    log "Creating new site: $site_name"

    # Set admin password
    local admin_pass="${ADMIN_PASSWORD:-admin}"

    # Create the site
    if [ "$DB_TYPE" = "postgres" ]; then
        bench new-site "$site_name" \
            --db-type postgres \
            --db-host "${DB_HOST:-db}" \
            --db-port "${DB_PORT:-5432}" \
            --db-name "${DB_NAME:-lending}" \
            --db-password "${DB_PASSWORD}" \
            --db-root-username "${DB_ROOT_USER:-postgres}" \
            --db-root-password "${DB_ROOT_PASSWORD:-$DB_PASSWORD}" \
            --admin-password "$admin_pass"
    else
        bench new-site "$site_name" \
            --db-host "${DB_HOST:-db}" \
            --db-port "${DB_PORT:-3306}" \
            --db-name "${DB_NAME:-lending}" \
            --db-password "${DB_PASSWORD}" \
            --db-root-username "${DB_ROOT_USER:-root}" \
            --db-root-password "${DB_ROOT_PASSWORD:-$DB_PASSWORD}" \
            --admin-password "$admin_pass" \
            --mariadb-user-host-login-scope='%'
    fi

    log "Site $site_name created successfully"

    # Set as default site
    bench use "$site_name"
}

install_apps() {
    local site_name="${SITE_NAME:-lending.localhost}"

    log "Installing apps on $site_name..."

    # Check if apps are already installed
    local installed_apps=$(bench --site "$site_name" list-apps 2>/dev/null || echo "")

    # Install ERPNext if not installed
    if ! echo "$installed_apps" | grep -q "erpnext"; then
        log "Installing ERPNext..."
        bench --site "$site_name" install-app erpnext || true
    fi

    # Install Payments if available and not installed
    if [ -d "apps/payments" ] && ! echo "$installed_apps" | grep -q "payments"; then
        log "Installing Payments..."
        bench --site "$site_name" install-app payments || true
    fi

    # Install Lending app
    if ! echo "$installed_apps" | grep -q "lending"; then
        log "Installing Lending..."
        bench --site "$site_name" install-app lending
    fi

    log "All apps installed successfully"
}

run_migrations() {
    local site_name="${SITE_NAME:-lending.localhost}"

    log "Running migrations..."
    bench --site "$site_name" migrate
    log "Migrations completed"
}

# =============================================================================
# Main Execution
# =============================================================================

case "$1" in
    "init")
        # Initialize new site
        log "=== Initializing Frappe Lending ==="
        wait_for_db
        wait_for_redis
        setup_common_site_config
        create_site
        install_apps
        run_migrations
        log "=== Initialization Complete ==="
        ;;

    "migrate")
        # Run migrations only
        log "=== Running Migrations ==="
        run_migrations
        log "=== Migrations Complete ==="
        ;;

    "dev")
        # Development mode
        log "=== Starting Development Server ==="
        wait_for_db
        wait_for_redis
        setup_common_site_config
        bench start
        ;;

    "prod"|"production")
        # Production mode with supervisor
        log "=== Starting Production Services ==="
        wait_for_db
        wait_for_redis
        setup_common_site_config

        # Check if site exists, if not initialize
        if [ ! -d "sites/${SITE_NAME:-lending.localhost}" ]; then
            log "Site not found, initializing..."
            create_site
            install_apps
            run_migrations
        fi

        # Start supervisor (manages gunicorn, workers, scheduler, socketio)
        exec /usr/bin/supervisord -c /home/frappe/supervisord.conf -n
        ;;

    "worker")
        # Run as worker only
        log "=== Starting Worker ==="
        bench worker --queue "${WORKER_QUEUE:-default}"
        ;;

    "scheduler")
        # Run scheduler only
        log "=== Starting Scheduler ==="
        bench schedule
        ;;

    "socketio")
        # Run socketio only
        log "=== Starting SocketIO ==="
        node apps/frappe/socketio.js
        ;;

    "console")
        # Interactive console
        bench --site "${SITE_NAME:-lending.localhost}" console
        ;;

    "shell")
        # Shell access
        /bin/bash
        ;;

    *)
        # Run custom command
        exec "$@"
        ;;
esac
