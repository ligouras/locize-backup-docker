# Locize Backup Solution

[![Production Ready](https://img.shields.io/badge/status-production%20ready-green.svg)](https://github.com/ligouras/locize/tree/main/docker-backup)
[![Docker](https://img.shields.io/badge/docker-supported-blue.svg)](Dockerfile)

Docker-based backup solution for Locize i18n projects using the official [`locize-cli`](https://github.com/locize/locize-cli). Supports local storage and AWS S3 with monitoring and reliability features.

## 🚀 Quick Start

```bash
# Clone and setup
git clone https://github.com/ligouras/locize.git
cd locize/docker-backup
cp .env.example .env
# Edit .env with your LOCIZE_PROJECT_ID

# Run backup
docker compose up --build
```

## 📋 Key Features

- **🔧 Reliable**: Native [`locize-cli`](backup.sh) integration with retry logic
- **🔒 Secure**: Non-root execution, minimal dependencies
- **⚡ Flexible**: Local or S3 storage with automatic cleanup
- **📊 Monitored**: Detailed logging and summary reports
- **🐳 Portable**: Docker, Kubernetes, Docker Swarm support
- **⏰ Smart**: 24-hour backup frequency control with force override

## 🛠️ Configuration

### Required Settings
```bash
LOCIZE_PROJECT_ID=your-project-id        # Required
LOCIZE_API_KEY=your-api-key              # Optional (for private projects)

# For S3 storage (optional)
S3_BUCKET_NAME=your-backup-bucket
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
```

### Optional Settings
```bash
LOCIZE_VERSION=latest                    # Default: latest
LOCIZE_LANGUAGES=en,fr,de                # Default: en,fr,de,ja,ko,zh
MAX_RETRIES=3                            # Default: 3
LOG_LEVEL=INFO                           # DEBUG, INFO, WARN, ERROR
```

See [`.env.example`](.env.example) for complete configuration reference.

## 📖 Usage

### Docker
```bash
# Basic usage
docker run --rm --env-file .env ligouras/locize-backup:latest

# Force backup (ignore 24-hour check)
docker run --rm --env-file .env ligouras/locize-backup:latest --force
```

### Docker Compose
```yaml
services:
  locize-backup:
    image: ligouras/locize-backup:latest
    env_file: .env
    volumes:
      - ./backup-data:/app/backup/data
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
```

### Cron Scheduling
```bash
# Daily at 2 AM
0 2 * * * docker run --rm --env-file .env ligouras/locize-backup:latest
```

## 📁 Output Structure

```
./backup-data/
├── 2024/01/15/
│   ├── i18n-frontend-en-20240115-120000.json
│   └── i18n-frontend-fr-20240115-120000.json
└── summaries/
    └── backup-summary-20240115-120000.json
```

## 🧪 Testing

```bash
# Local testing
npm run test:local

# S3 testing with MinIO
npm run minio:start
npm run test:minio
npm run minio:console  # http://localhost:9001
npm run minio:stop
```

## 🔧 Development

```bash
npm run build              # Build Docker image
npm run test               # Run integration tests
npm run lint               # Lint scripts
npm run help               # Show all commands
```

## 🐛 Troubleshooting

### Common Issues

**Missing Dependencies**
```
[ERROR] Missing required dependencies: locize
```
*Solution*: Use correct base image `ligouras/locize-cli:latest`

**Configuration Errors**
```
[ERROR] LOCIZE_PROJECT_ID is required
```
*Solution*: Set required environment variables in `.env`

**API Access Issues**
```
[WARN] locize-cli download failed
```
*Solution*: Check project ID, API key, and network connectivity

### Debug Commands
```bash
# Test container health
docker run --rm ligouras/locize-backup:latest bash -c "locize --version"

# Debug logging
docker run --rm -e LOG_LEVEL=DEBUG --env-file .env ligouras/locize-backup:latest

# Interactive debugging
docker run --rm -it --env-file .env ligouras/locize-backup:latest bash
```

## 📚 Architecture

- **Base**: [`ligouras/locize-cli:10.3.2`](https://hub.docker.com/r/ligouras/locize-cli)
- **Security**: Non-root execution (UID 1001)
- **Key Files**: [`Dockerfile`](Dockerfile), [`backup.sh`](backup.sh), [`.env.example`](.env.example)

---

**Version**: 10.3.2 | **License**: MIT