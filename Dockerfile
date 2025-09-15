# Locize Backup Container with locize-cli
# Uses ligouras/locize-cli with version pinning for enhanced functionality

# Build arguments for version pinning and metadata
ARG LOCIZE_CLI_VERSION

FROM ligouras/locize-cli:${LOCIZE_CLI_VERSION}

# Build arguments for metadata labels (after FROM to ensure they're available)
ARG LOCIZE_CLI_VERSION
ARG BUILD_DATE="unknown"
ARG VCS_REF="unknown"

# Set OCI-compliant metadata labels
LABEL org.opencontainers.image.title="locize-backup"
LABEL org.opencontainers.image.description="Locize i18n backup script using locize-cli for Kubernetes environments"
LABEL org.opencontainers.image.version="${LOCIZE_CLI_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.source="https://github.com/ligouras/locize-backup-docker"
LABEL org.opencontainers.image.url="https://github.com/ligouras/locize-backup-docker"
LABEL org.opencontainers.image.documentation="https://github.com/ligouras/locize-backup-docker#readme"
LABEL org.opencontainers.image.vendor="ligouras"
LABEL org.opencontainers.image.licenses="MIT"
LABEL maintainer="locize-backup"

# Switch to root temporarily to install additional dependencies
USER root

# Install additional runtime dependencies for backup functionality
RUN apk add --no-cache \
    bash \
    jq \
    aws-cli \
    bc \
    ca-certificates \
    tzdata \
    curl \
    && rm -rf /var/cache/apk/*

# Create backup-specific directories and ensure proper ownership
RUN mkdir -p /app/backup/data && \
    chown -R locize:nodejs /app/backup

# Copy the enhanced backup script
COPY --chown=locize:nodejs backup.sh /app/backup/

# Make script executable
RUN chmod +x /app/backup/backup.sh

# Set working directory for backup operations
WORKDIR /app/backup

# Switch back to non-root user for security
USER locize

# Set default environment variables for backup functionality
ENV LOG_LEVEL=INFO
ENV CLEANUP_LOCAL_FILES=true
ENV MAX_RETRIES=3
ENV RETRY_DELAY=5
ENV RATE_LIMIT_DELAY=1
ENV LOCIZE_CLI_TIMEOUT=30

# Health check - verify locize-cli and backup script are accessible
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD locize --version && test -x /app/backup/backup.sh || exit 1

# Override entrypoint to use backup script by default
ENTRYPOINT ["/app/backup/backup.sh"]

# Default command (can be overridden)
CMD []