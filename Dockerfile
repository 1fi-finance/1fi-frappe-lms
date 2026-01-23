# Frappe Lending - Production Dockerfile
# Uses official Frappe base images for reliability

# =============================================================================
# Stage 1: Build stage using official Frappe builder
# =============================================================================
FROM frappe/bench:latest AS builder

# Configure git (required for bench operations)
RUN git config --global user.name "Frappe Build" \
    && git config --global user.email "build@frappe.local" \
    && git config --global init.defaultBranch main \
    && git config --global advice.detachedHead false

WORKDIR /home/frappe

# Initialize bench with Frappe version-15
ARG FRAPPE_BRANCH=version-15
RUN bench init \
    --frappe-branch ${FRAPPE_BRANCH} \
    --skip-redis-config-generation \
    --skip-assets \
    frappe-bench

WORKDIR /home/frappe/frappe-bench

# Get ERPNext (required dependency for lending)
ARG ERPNEXT_BRANCH=version-15
RUN bench get-app --branch ${ERPNEXT_BRANCH} erpnext

# Get Payments app (optional but recommended)
ARG PAYMENTS_BRANCH=version-15
RUN bench get-app --branch ${PAYMENTS_BRANCH} payments || echo "Payments app skipped"

# Copy lending app
COPY --chown=frappe:frappe . /home/frappe/frappe-bench/apps/lending

# Install app dependencies and build assets
RUN bench setup requirements --dev \
    && bench build --production

# =============================================================================
# Stage 2: Production image
# =============================================================================
FROM frappe/frappe-worker:v15 AS production

USER root

# Install additional dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor \
    curl \
    && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe

# Copy bench from builder stage
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

# Copy configuration files
COPY --chown=frappe:frappe docker/supervisord.conf /home/frappe/supervisord.conf
COPY --chown=frappe:frappe docker/entrypoint.sh /home/frappe/entrypoint.sh

USER root
RUN chmod +x /home/frappe/entrypoint.sh

USER frappe

# Expose ports
# 8000 - Frappe web
# 9000 - SocketIO
EXPOSE 8000 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:8000/api/method/ping || exit 1

ENTRYPOINT ["/home/frappe/entrypoint.sh"]
CMD ["prod"]
