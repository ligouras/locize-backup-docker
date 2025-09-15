# Locize Backup Solution

[![Production Ready](https://img.shields.io/badge/status-production%20ready-green.svg)](https://github.com/ligouras/locize/tree/main/docker-backup)
[![Docker](https://img.shields.io/badge/docker-supported-blue.svg)](Dockerfile)
[![Version](https://img.shields.io/badge/version-10.3.2-brightgreen.svg)](https://github.com/ligouras/locize/tree/main/docker-backup)

Enterprise-grade Docker-based backup solution for Locize i18n projects using the official [`locize-cli`](https://github.com/locize/locize-cli). Supports both local storage and AWS S3 with comprehensive monitoring and reliability features.

## 🚀 Quick Start

### Prerequisites
- Docker installed
- Locize project ID
- (Optional) AWS S3 bucket for cloud backups

### 30-Second Setup

```bash
# 1. Clone and navigate
git clone https://github.com/ligouras/locize.git
cd locize/docker-backup

# 2. Configure environment
cp .env.example .env
# Edit .env with your LOCIZE_PROJECT_ID and optionally S3_BUCKET_NAME

# 3. Run backup
docker compose up --build
```

### Verify Success
```bash
# Check local backups
ls -la ./backup-data/

# Or check S3 (if configured)
aws s3 ls s3://your-bucket/$(date +%Y/%m/%d)/
```

## 📋 Key Features

- **🔧 Enhanced Reliability**: Native [`locize-cli`](backup.sh) integration with retry logic and timeout control
- **🔒 Enterprise Security**: Non-root execution, minimal dependencies, secure defaults
- **⚡ Flexible Storage**: Local-only or S3 backup with automatic cleanup options
- **📊 Comprehensive Monitoring**: Detailed logging, summary reports, and health checks
- **🐳 Multi-Platform**: Docker, Kubernetes, Docker Swarm support
- **⏰ Smart Scheduling**: Built-in 24-hour backup frequency control with force override

## 🛠️ Configuration

### Environment Files Structure

The project uses split environment files for better organization:

- **[`.env.local`](.env.local)** - Base Locize and backup settings
- **[`.env.s3`](.env.s3)** - AWS S3 production configuration
- **[`.env.minio`](.env.minio)** - MinIO testing configuration
- **[`.env.example`](.env.example)** - Complete configuration reference

### Required Settings

```bash
# Locize Project Configuration
LOCIZE_PROJECT_ID=your-project-id        # Required
LOCIZE_API_KEY=your-api-key              # Optional (for private projects)
LOCIZE_VERSION=latest                    # Optional (default: latest)
LOCIZE_LANGUAGES=en,fr,de                # Optional (default: en,fr,de,ja,ko,zh)
LOCIZE_NAMESPACES=frontend,backend       # Optional (default: frontend,backend-templates,configurations-schemes,configurations-forms)

# Storage Configuration (choose one)
# Option 1: Local storage only (default)
# No additional configuration needed

# Option 2: S3 storage
S3_BUCKET_NAME=your-backup-bucket        # Enables S3 storage
AWS_REGION=us-east-1                     # Required with S3
AWS_ACCESS_KEY_ID=your-access-key        # Or use AWS_PROFILE/IAM roles
AWS_SECRET_ACCESS_KEY=your-secret-key    # Required with access key
```

### Optional Settings

```bash
# Backup Behavior
MAX_RETRIES=3                            # Retry attempts (default: 3)
RETRY_DELAY=5                           # Delay between retries in seconds (default: 5)
RATE_LIMIT_DELAY=1                      # Delay between API calls (default: 1)
CLEANUP_LOCAL_FILES=true                # Clean up after S3 upload (default: true)
LOCIZE_CLI_TIMEOUT=30                   # CLI timeout in seconds (default: 30)

# Logging
LOG_LEVEL=INFO                          # DEBUG, INFO, WARN, ERROR (default: INFO)
```

## 📖 Usage Examples

### Docker

```bash
# Basic usage with environment file
docker run --rm --env-file .env ligouras/locize-backup:latest

# With custom settings
docker run --rm \
  -e LOCIZE_PROJECT_ID=your-project-id \
  -e S3_BUCKET_NAME=your-bucket \
  -e LOG_LEVEL=DEBUG \
  ligouras/locize-backup:latest

# Force backup (ignore 24-hour check)
docker run --rm --env-file .env ligouras/locize-backup:latest --force
```

### Docker Compose

```yaml
# docker-compose.yml
services:
  locize-backup:
    image: ligouras/locize-backup:latest
    env_file: .env
    volumes:
      - ./backup-data:/app/backup/data  # For local inspection
    restart: unless-stopped
```

### Kubernetes CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: locize-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: locize-backup
            image: ligouras/locize-backup:latest
            envFrom:
            - configMapRef:
                name: locize-backup-config
            - secretRef:
                name: locize-backup-secrets
            resources:
              requests:
                memory: "256Mi"
                cpu: "250m"
              limits:
                memory: "512Mi"
                cpu: "500m"
          restartPolicy: OnFailure
```

### Scheduling with Cron

```bash
# Daily at 2 AM UTC
0 2 * * * docker run --rm --env-file /opt/locize-backup/.env ligouras/locize-backup:latest

# Every 6 hours
0 */6 * * * docker run --rm --env-file /opt/locize-backup/.env ligouras/locize-backup:latest
```

## 📁 Output Structure

### Local Storage
```
./backup-data/
├── 2024/01/15/
│   ├── i18n-frontend-en-20240115-120000.json
│   ├── i18n-frontend-fr-20240115-120000.json
│   └── ...
└── summaries/
    └── backup-summary-20240115-120000.json
```

### S3 Storage
```
s3://your-bucket/
├── 2024/01/15/
│   ├── i18n-frontend-en-20240115-120000.json
│   ├── i18n-frontend-fr-20240115-120000.json
│   └── ...
└── summaries/
    └── backup-summary-20240115-120000.json
```

### Summary Report Example
```json
{
  "timestamp": "20240115-120000",
  "project_id": "your-project-id",
  "version": "latest",
  "backup_date": "2024-01-15 12:00:00 UTC",
  "total_combinations": 24,
  "successful": 24,
  "failed": 0,
  "success_rate": 100.00,
  "storage_type": "s3",
  "s3_bucket": "your-backup-bucket",
  "backup_method": "locize-cli",
  "cli_version": "10.3.2"
}
```

## 🧪 Testing

### Local Testing
```bash
# Test local storage only
npm run test:local

# Test with debug logging
LOG_LEVEL=DEBUG npm run test:local

# Check results
ls -la ./backup-data/
```

### S3 Testing with MinIO
```bash
# Start MinIO test environment
npm run minio:start

# Test S3 backup with MinIO
npm run test:minio

# Access MinIO console
npm run minio:console
# Opens http://localhost:9001 (minioadmin/minioadmin123)

# Cleanup
npm run minio:stop
```

### Available Test Scripts
```bash
npm run test:local          # Local storage test
npm run test:minio          # MinIO S3 test
npm run test:smoke          # Quick health check
npm run minio:start         # Start MinIO environment
npm run minio:stop          # Stop MinIO environment
npm run minio:console       # Open MinIO console
```

## 🔧 Development

### Building
```bash
# Build image
npm run build

# Build with no cache
npm run build:force

# Build multi-platform
npm run build:multi
```

### Available Scripts
```bash
npm run build              # Build Docker image
npm run build:push         # Build and push to registry
npm run test               # Run integration tests
npm run lint               # Lint Dockerfile and shell scripts
npm run clean              # Clean up Docker resources
npm run version            # Show current version
npm run help               # Show all available scripts
```

## 🐛 Troubleshooting

### Common Issues

**Missing Dependencies**
```
[ERROR] Missing required dependencies: locize
```
*Solution*: Ensure using the correct base image `ligouras/locize-cli:latest`

**Configuration Errors**
```
[ERROR] Configuration validation failed: LOCIZE_PROJECT_ID is required
```
*Solution*: Set all required environment variables in your `.env` file

**API Access Issues**
```
[WARN] locize-cli download failed: en/frontend
```
*Solution*: Check project ID, API key (for private projects), and network connectivity

**S3 Upload Failures**
```
[ERROR] Failed to upload to S3 after 3 attempts
```
*Solution*: Verify AWS credentials, S3 bucket permissions, and network connectivity

### Debugging Steps

```bash
# 1. Test container health
docker run --rm ligouras/locize-backup:latest bash -c "locize --version"

# 2. Test with debug logging
docker run --rm -e LOG_LEVEL=DEBUG --env-file .env ligouras/locize-backup:latest

# 3. Interactive debugging
docker run --rm -it --env-file .env ligouras/locize-backup:latest bash

# 4. Check S3 connectivity (if using S3)
docker run --rm --env-file .env ligouras/locize-backup:latest bash -c "aws s3 ls"
```

### Log Levels
- **ERROR**: Critical errors and failures
- **WARN**: Warnings and retry attempts
- **INFO**: General information and progress (default)
- **DEBUG**: Detailed debugging information

## 📚 Architecture

### Base Image
- **Base**: [`ligouras/locize-cli:10.3.2`](https://hub.docker.com/r/ligouras/locize-cli)
- **Additional Dependencies**: bash, jq, aws-cli, bc, ca-certificates, tzdata, curl
- **Security**: Non-root user execution (locize:nodejs, UID 1001)
- **Working Directory**: `/app/backup`

### Key Files
- **[`Dockerfile`](Dockerfile)** - Container definition with security best practices
- **[`backup.sh`](backup.sh)** - Main backup script with locize-cli integration
- **[`docker-compose.yml`](docker-compose.yml)** - Development and testing setup
- **[`.env.example`](.env.example)** - Complete configuration reference

## 🆘 Support

### Getting Help
1. **Check Documentation**: Review troubleshooting sections above
2. **Enable Debug Logging**: Set `LOG_LEVEL=DEBUG` and examine container logs
3. **Verify Configuration**: Compare your settings against [`.env.example`](.env.example)
4. **Test Minimal Setup**: Start with basic configuration and add complexity gradually

### Health Checks
```bash
# Container health check
docker run --rm ligouras/locize-backup:latest bash -c "locize --version && test -x /app/backup/backup.sh"

# Test backup functionality
docker run --rm --env-file .env ligouras/locize-backup:latest --force
```

---

**Status**: ✅ Production Ready | **Version**: 10.3.2 | **License**: MIT