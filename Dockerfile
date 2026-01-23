# Frappe Lending - Production Dockerfile
# Uses official frappe/erpnext image which includes Frappe + ERPNext

# =============================================================================
# Stage 1: Build stage - Add lending app
# =============================================================================
FROM frappe/erpnext:v15 AS builder

USER root

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe/frappe-bench

# Configure git (required for bench operations)
RUN git config --global user.name "Frappe Build" \
    && git config --global user.email "build@frappe.local" \
    && git config --global advice.detachedHead false

# Copy lending app
COPY --chown=frappe:frappe . /home/frappe/frappe-bench/apps/lending

# Install lending app as Python package and build assets
RUN ./env/bin/pip install -e apps/lending \
    && echo "lending" >> sites/apps.txt \
    && bench build --production

# =============================================================================
# Stage 2: Production image
# =============================================================================
FROM frappe/erpnext:v15 AS production

USER root

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor \
    curl \
    && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe/frappe-bench

# Configure git for runtime
RUN git config --global user.name "Frappe" \
    && git config --global user.email "frappe@localhost"

# Copy the lending app from builder
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench/apps/lending /home/frappe/frappe-bench/apps/lending

# Copy built assets from builder
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/sites/assets

# Copy apps.txt with lending added
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench/sites/apps.txt /home/frappe/frappe-bench/sites/apps.txt

# Install lending app as Python package in production image
RUN ./env/bin/pip install -e apps/lending

# Copy configuration files
COPY --chown=frappe:frappe docker/supervisord.conf /home/frappe/supervisord.conf
COPY --chown=frappe:frappe docker/entrypoint.sh /home/frappe/entrypoint.sh

USER root
RUN chmod +x /home/frappe/entrypoint.sh

USER frappe

# Expose ports
EXPOSE 8000 9000

# Health check - increased start_period for first-time installation (can take 10+ minutes)
HEALTHCHECK --interval=60s --timeout=30s --start-period=900s --retries=5 \
    CMD curl -f http://localhost:8000/api/method/ping || exit 1

ENTRYPOINT ["/home/frappe/entrypoint.sh"]
CMD ["prod"]
