# Locize Backup Docker Image

[![Production Ready](https://img.shields.io/badge/status-production%20ready-green.svg)](https://github.com/ligouras/locize/tree/main/docker-backup)
[![Docker](https://img.shields.io/badge/docker-supported-blue.svg)](Dockerfile)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A production-ready Docker image for automated backup of Locize i18n projects using the official [locize-cli](https://github.com/locize/locize-cli). Supports local storage and AWS S3 with monitoring and reliability features.

## Why Use This Docker Image?

### Benefits
- **Reliable Backups**: Native locize-cli integration with retry logic and error handling
- **Flexible Storage**: Support for local filesystem and AWS S3 storage options
- **Smart Scheduling**: 24-hour backup frequency control with force override capability
- **Secure**: Non-root execution with minimal dependencies
- **Portable**: Works with Docker, Docker Compose, Kubernetes, and cron scheduling
- **Monitored**: Detailed logging and summary reports for backup operations

### Perfect For
- **Automated Backups**: Schedule regular backups of your Locize translation projects
- **CI/CD Integration**: Include backup operations in your deployment pipelines
- **Disaster Recovery**: Maintain reliable backups with configurable storage options
- **Multi-Environment**: Consistent backup behavior across development and production

## Installation

### Option 1: Docker Hub (Recommended)
```bash
docker pull ligouras/locize-backup:latest
```

### Option 2: Build Locally
```bash
git clone https://github.com/ligouras/locize.git
cd locize/docker-backup
npm run build
```

## Quick Start

### Basic Setup
```bash
# Clone and setup
git clone https://github.com/ligouras/locize.git
cd locize/docker-backup
cp .env.example .env
# Edit .env with your LOCIZE_PROJECT_ID

# Run backup
docker compose up --build
```

### Basic Commands
```bash
# Run backup with environment file
docker run --rm --env-file .env ligouras/locize-backup:latest

# Force backup (ignore 24-hour check)
docker run --rm --env-file .env ligouras/locize-backup:latest --force

# Run without summary report
docker run --rm --env-file .env ligouras/locize-backup:latest --no-summary

# Use flat structure (no date folders)
docker run --rm --env-file .env ligouras/locize-backup:latest --flat-structure

# Check version
docker run --rm ligouras/locize-backup:latest bash -c "locize --version"
```

## Common Use Cases

### 1. Docker Compose Deployment
```yaml
services:
  locize-backup:
    image: ligouras/locize-backup:latest
    env_file: .env
    volumes:
      - ./backup-data:/app/backup/data
```

### 2. Kubernetes CronJob
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
```

### 3. Cron Scheduling
```bash
# Daily at 2 AM
0 2 * * * docker run --rm --env-file .env ligouras/locize-backup:latest
```

### 4. S3 Storage Configuration
```bash
# Required for S3 storage
docker run --rm \
  -e LOCIZE_PROJECT_ID=your-project-id \
  -e S3_BUCKET_NAME=your-backup-bucket \
  -e AWS_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID=your-access-key \
  -e AWS_SECRET_ACCESS_KEY=your-secret-key \
  ligouras/locize-backup:latest
```

## Available npm Scripts

For local development and testing:

```bash
npm run build              # Build Docker image
npm run test               # Run integration tests
npm run test:local         # Local testing
npm run test:minio         # S3 testing with MinIO
npm run minio:start        # Start MinIO for testing
npm run minio:console      # Access MinIO console (http://localhost:9001)
npm run minio:stop         # Stop MinIO
npm run lint               # Lint scripts
npm run help               # Show all commands
```

## Image Details

### Base Image
- **Base**: `ligouras/locize-cli:10.3.2` (includes locize-cli and dependencies)
- **Size**: Optimized for production use
- **Platforms**: `linux/amd64`, `linux/arm64`

### Security Features
- **Non-root user**: Runs as user with UID 1001
- **Minimal surface**: Only essential packages included
- **Secure defaults**: Safe configuration options

### Output Structure

**Date-based structure (default):**
```
./backup-data/
├── 2024/01/15/
│   ├── i18n-frontend-en.json
│   └── i18n-frontend-fr.json
└── summaries/
    └── backup-summary-20240115-120000.json
```

**Flat structure (with `--flat-structure` flag):**
```
./backup-data/
├── i18n-frontend-en.json
├── i18n-frontend-fr.json
└── summaries/
    └── backup-summary-20240115-120000.json
```

## Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `LOCIZE_PROJECT_ID` | Your locize project ID (required) | - | `abc123def-456-789` |
| `LOCIZE_API_KEY` | Your locize API key (optional for public projects) | - | `your-secret-api-key` |
| `LOCIZE_VERSION` | Specific version to backup | `latest` | `latest` or `production` |
| `LOCIZE_LANGUAGES` | Languages to backup | `en,fr,de,ja,ko,zh` | `en,fr,de` |
| `S3_BUCKET_NAME` | S3 bucket for backups (optional) | - | `my-backup-bucket` |
| `AWS_REGION` | AWS region for S3 | `us-east-1` | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | AWS access key for S3 | - | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key for S3 | - | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `MAX_RETRIES` | Maximum retry attempts | `3` | `3` |
| `RETRY_DELAY` | Delay between retries (seconds) | `5` | `5` |
| `RATE_LIMIT_DELAY` | Delay between API calls (seconds) | `1` | `1` |
| `LOCIZE_CLI_TIMEOUT` | Timeout for locize-cli commands (seconds) | `30` | `30` |
| `CLEANUP_LOCAL_FILES` | Remove local files after S3 upload | `true` | `true`, `false` |
| `LOG_LEVEL` | Logging level | `INFO` | `DEBUG`, `INFO`, `WARN`, `ERROR` |

See [`.env.example`](.env.example) for complete configuration reference.

## Requirements

- **Docker**: 20.0.0 or higher
- **For local builds**: Node.js 14.0.0 or higher (for npm scripts)
- **For S3 storage**: Valid AWS credentials and S3 bucket
- **For development**: Git, Docker Buildx

## Related Projects

- **[locize-cli](https://github.com/locize/locize-cli)** - The official CLI tool for locize
- **[docker-cli](../docker-cli/)** - Docker image for locize-cli

---

**Version**: 10.3.2 | **License**: MIT