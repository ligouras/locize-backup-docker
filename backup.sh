#!/bin/bash

# Locize i18n Backup Script using locize-cli
# This script downloads internationalization files using locize-cli and uploads them to S3
# Designed for automated execution in Kubernetes environments

set -euo pipefail

FORCE_BACKUP="false"

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_BACKUP="true"
                log_info "Force backup mode enabled"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Locize i18n Backup Script

Usage: $0 [OPTIONS]

OPTIONS:
    --force     Force backup even if one was run within the last 24 hours
    -h, --help  Show this help message

DESCRIPTION:
    This script downloads internationalization files using locize-cli and
    optionally uploads them to S3. By default, it will exit if a backup
    was already performed within the last 24 hours.

EXAMPLES:
    $0                # Run backup (skip if run within 24 hours)
    $0 --force        # Force backup regardless of timing
EOF
}

# Default configuration (can be overridden by environment variables)
PROJECT_ID="${LOCIZE_PROJECT_ID:-9ad9654a-7325-49cf-bca2-141a262ef86a}"
API_KEY="${LOCIZE_API_KEY:-}"
LANGUAGES="${LOCIZE_LANGUAGES:-en,fr,de,ja,ko,zh}"
NAMESPACES="${LOCIZE_NAMESPACES:-frontend,backend-templates,configurations-schemes,configurations-forms}"
VERSION="${LOCIZE_VERSION:-latest}"
S3_BUCKET="${S3_BUCKET_NAME:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/app/backup/data"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"
RATE_LIMIT_DELAY="${RATE_LIMIT_DELAY:-1}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
CLEANUP_LOCAL_FILES="${CLEANUP_LOCAL_FILES:-true}"
LOCIZE_CLI_TIMEOUT="${LOCIZE_CLI_TIMEOUT:-30}"

# Determine storage mode
USE_S3="false"
if [[ -n "$S3_BUCKET" ]]; then
    USE_S3="true"
fi

# Color codes for log levels
readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

    case "$level" in
        ERROR)
            echo -e "[$timestamp] [${RED}ERROR${NC}] $message" >&2
            ;;
        WARN)
            echo -e "[$timestamp] [${YELLOW}WARN${NC}] $message" >&2
            ;;
        SUCCESS)
            if [[ "$LOG_LEVEL" != "ERROR" ]]; then
                echo -e "[$timestamp] [${GREEN}SUCCESS${NC}] $message"
            fi
            ;;
        INFO)
            if [[ "$LOG_LEVEL" != "ERROR" ]]; then
                echo -e "[$timestamp] [${CYAN}INFO${NC}] $message"
            fi
            ;;
        DEBUG)
            if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "[$timestamp] [${BLUE}DEBUG${NC}] $message"
            fi
            ;;
    esac
}

log_error() { log "ERROR" "$@"; }
log_warn() { log "WARN" "$@"; }
log_success() { log "SUCCESS" "$@"; }
log_info() { log "INFO" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Check if required tools are available
check_dependencies() {
    local missing_deps=()

    # Always required dependencies
    for cmd in locize jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    # AWS CLI is only required if using S3
    if [[ "$USE_S3" == "true" ]]; then
        if ! command -v "aws" &> /dev/null; then
            missing_deps+=("aws")
        fi
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        if [[ "$USE_S3" == "true" ]]; then
            log_error "Please install: locize-cli, jq, aws-cli"
        else
            log_error "Please install: locize-cli, jq"
        fi
        exit 1
    fi

    log_debug "All required dependencies are available"
    if [[ "$USE_S3" == "true" ]]; then
        log_debug "S3 storage mode enabled"
    else
        log_debug "Local storage mode enabled"
    fi
}

# Validate environment variables
validate_config() {
    local errors=()

    if [[ -z "$PROJECT_ID" ]]; then
        errors+=("LOCIZE_PROJECT_ID is required")
    fi

    # S3 configuration is optional
    if [[ "$USE_S3" == "true" ]]; then
        if [[ -z "$S3_BUCKET" ]]; then
            errors+=("S3_BUCKET_NAME is required when using S3 storage")
        fi
        if [[ -z "$AWS_REGION" ]]; then
            errors+=("AWS_REGION is required when using S3 storage")
        fi

        # Check AWS credentials when using S3
        if [[ -z "$AWS_ACCESS_KEY_ID" && -z "$AWS_PROFILE" ]]; then
            log_warn "No AWS credentials found (AWS_ACCESS_KEY_ID or AWS_PROFILE). Assuming IAM role or instance profile is configured."
        elif [[ -n "$AWS_ACCESS_KEY_ID" && -z "$AWS_SECRET_ACCESS_KEY" ]]; then
            errors+=("AWS_SECRET_ACCESS_KEY is required when AWS_ACCESS_KEY_ID is set")
        fi

        log_info "S3 storage configured: s3://$S3_BUCKET"
        if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
            log_debug "Using AWS Access Key ID: ${AWS_ACCESS_KEY_ID:0:8}..."
        elif [[ -n "$AWS_PROFILE" ]]; then
            log_debug "Using AWS Profile: $AWS_PROFILE"
        else
            log_debug "Using IAM role or instance profile for AWS authentication"
        fi
    else
        log_info "Local storage configured: $BACKUP_DIR"
        # Ensure CLEANUP_LOCAL_FILES is false when using local storage only
        if [[ "$CLEANUP_LOCAL_FILES" == "true" ]]; then
            log_warn "CLEANUP_LOCAL_FILES is set to true but using local storage - setting to false"
            CLEANUP_LOCAL_FILES="false"
        fi
    fi

    # API key is optional for public projects, but warn if missing
    if [[ -z "$API_KEY" ]]; then
        log_warn "LOCIZE_API_KEY not set - only public projects will be accessible"
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Configuration validation failed:"
        printf '%s\n' "${errors[@]}" >&2
        exit 1
    fi

    log_debug "Configuration validation passed"
}

# Create backup directory with legacy structure
setup_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log_debug "Created backup directory: $BACKUP_DIR"
    fi

    # Create subdirectories for organization matching legacy structure: YYYY/MM/DD
    local date_path=$(date -u '+%Y/%m/%d')
    local daily_dir="$BACKUP_DIR/$date_path"

    if [[ ! -d "$daily_dir" ]]; then
        mkdir -p "$daily_dir"
        log_debug "Created daily backup directory: $daily_dir"
    fi

    # Create summaries directory
    local summaries_dir="$BACKUP_DIR/summaries"
    if [[ ! -d "$summaries_dir" ]]; then
        mkdir -p "$summaries_dir"
        log_debug "Created summaries directory: $summaries_dir"
    fi

    echo "$daily_dir"
}

# Validate JSON content
validate_json() {
    local file="$1"

    if ! jq empty "$file" 2>/dev/null; then
        log_error "Invalid JSON in file: $file"
        return 1
    fi

    # Check if file is not empty
    if [[ ! -s "$file" ]]; then
        log_error "Empty file: $file"
        return 1
    fi

    log_debug "JSON validation passed for: $file"
    return 0
}

# Check if backup was run within the last 24 hours
check_last_backup_time() {
    local summaries_dir="$BACKUP_DIR/summaries"

    # If summaries directory doesn't exist, no previous backups
    if [[ ! -d "$summaries_dir" ]]; then
        log_debug "No summaries directory found, proceeding with backup"
        return 0
    fi

    # Find the most recent summary file
    local latest_summary
    latest_summary=$(find "$summaries_dir" -name "backup-summary-*.json" -type f 2>/dev/null | sort -r | head -1)

    if [[ -z "$latest_summary" || ! -f "$latest_summary" ]]; then
        log_debug "No previous backup summaries found, proceeding with backup"
        return 0
    fi

    log_debug "Found latest summary: $(basename "$latest_summary")"

    # Extract timestamp from summary file
    local last_backup_timestamp
    if ! last_backup_timestamp=$(jq -r '.timestamp // empty' "$latest_summary" 2>/dev/null); then
        log_warn "Could not parse timestamp from summary file, proceeding with backup"
        return 0
    fi

    if [[ -z "$last_backup_timestamp" ]]; then
        log_warn "No timestamp found in summary file, proceeding with backup"
        return 0
    fi

    # Convert timestamp to epoch seconds (format: YYYYMMDD-HHMMSS)
    local last_backup_date="${last_backup_timestamp:0:8}"
    local last_backup_time="${last_backup_timestamp:9:6}"

    # Reformat to YYYY-MM-DD HH:MM:SS for date parsing
    local formatted_date="${last_backup_date:0:4}-${last_backup_date:4:2}-${last_backup_date:6:2}"
    local formatted_time="${last_backup_time:0:2}:${last_backup_time:2:2}:${last_backup_time:4:2}"
    local last_backup_epoch

    # Try different date parsing methods for compatibility
    if last_backup_epoch=$(date -d "$formatted_date $formatted_time UTC" +%s 2>/dev/null); then
        log_debug "Successfully parsed timestamp using date -d"
    elif last_backup_epoch=$(date -u -d "$formatted_date $formatted_time" +%s 2>/dev/null); then
        log_debug "Successfully parsed timestamp using date -u -d"
    elif last_backup_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$formatted_date $formatted_time" +%s 2>/dev/null); then
        log_debug "Successfully parsed timestamp using date -j -f (BSD/macOS)"
    else
        log_warn "Could not parse backup timestamp: $last_backup_timestamp, proceeding with backup"
        return 0
    fi

    # Get current time in epoch seconds
    local current_epoch
    current_epoch=$(date +%s)

    # Calculate time difference in seconds (24 hours = 86400 seconds)
    local time_diff=$((current_epoch - last_backup_epoch))
    local hours_since_backup=$((time_diff / 3600))

    log_debug "Last backup was $hours_since_backup hours ago"

    # Check if less than 24 hours have passed
    if [[ $time_diff -lt 86400 ]]; then
        local remaining_hours=$((24 - hours_since_backup))
        log_info "Last backup was performed $hours_since_backup hours ago (less than 24 hours)"

        if [[ "$FORCE_BACKUP" == "true" ]]; then
            log_info "Force mode enabled, proceeding with backup despite recent execution"
            return 0
        else
            log_info "Backup already performed within the last 24 hours"
            log_info "Next backup can be performed in approximately $remaining_hours hours"
            log_info "Use --force flag to override this check"
            exit 0
        fi
    else
        log_info "Last backup was $hours_since_backup hours ago, proceeding with new backup"
        return 0
    fi
}

# Download namespace using locize-cli with retry logic
download_with_locize_cli() {
    local language="$1"
    local namespace="$2"
    local output_file="$3"
    local attempt=1

    while [[ $attempt -le $MAX_RETRIES ]]; do
        log_debug "Download attempt $attempt/$MAX_RETRIES for $language/$namespace"

        # Create temporary directory for locize-cli download
        local temp_dir=$(mktemp -d)
        local locize_args=()

        # Build locize-cli command arguments
        locize_args+=(download)
        locize_args+=(--project-id "$PROJECT_ID")
        locize_args+=(--language "$language")
        locize_args+=(--namespace "$namespace")
        locize_args+=(--path "$temp_dir")
        locize_args+=(--format json)

        # Add version if not latest
        if [[ "$VERSION" != "latest" ]]; then
            locize_args+=(--version "$VERSION")
        fi

        # Add API key if provided
        if [[ -n "$API_KEY" ]]; then
            locize_args+=(--api-key "$API_KEY")
        fi

        # Execute locize-cli command with timeout
        if timeout "$LOCIZE_CLI_TIMEOUT" locize "${locize_args[@]}" 2>/dev/null; then
            # Find the downloaded file - locize-cli may create different structures
            local downloaded_file=""

            # Try different possible file locations
            if [[ -f "$temp_dir/$language/$namespace.json" ]]; then
                downloaded_file="$temp_dir/$language/$namespace.json"
            elif [[ -f "$temp_dir/$namespace.json" ]]; then
                downloaded_file="$temp_dir/$namespace.json"
            elif [[ -f "$temp_dir/$language.json" ]]; then
                downloaded_file="$temp_dir/$language.json"
            else
                # Find any JSON file in the temp directory
                downloaded_file=$(find "$temp_dir" -name "*.json" -type f | head -1)
            fi

            if [[ -n "$downloaded_file" && -f "$downloaded_file" ]]; then
                mv "$downloaded_file" "$output_file"
                rm -rf "$temp_dir"

                if validate_json "$output_file"; then
                    log_debug "Downloaded and validated: $(basename "$output_file")"
                    return 0
                else
                    log_warn "Downloaded file failed JSON validation: $output_file"
                    rm -f "$output_file"
                fi
            else
                log_warn "No JSON file found after download in: $temp_dir"
                log_debug "Contents of temp dir: $(ls -la "$temp_dir" 2>/dev/null || echo 'empty')"
                rm -rf "$temp_dir"
            fi
        else
            log_warn "locize-cli download failed (attempt $attempt/$MAX_RETRIES): $language/$namespace"
            rm -rf "$temp_dir"
        fi

        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_debug "Waiting ${RETRY_DELAY}s before retry..."
            sleep "$RETRY_DELAY"
        fi

        ((attempt++))
    done

    log_error "Failed to download after $MAX_RETRIES attempts: $language/$namespace"
    return 1
}

# Upload file to S3 with retry logic
upload_to_s3() {
    local local_file="$1"
    local s3_key="$2"
    local attempt=1

    while [[ $attempt -le $MAX_RETRIES ]]; do
        log_debug "S3 upload attempt $attempt/$MAX_RETRIES for $(basename "$s3_key")"

        # Build AWS CLI command with optional endpoint URL for MinIO
        local aws_cmd=(aws s3 cp "$local_file" "s3://$S3_BUCKET/$s3_key")
        aws_cmd+=(--region "$AWS_REGION")
        aws_cmd+=(--storage-class STANDARD_IA)
        aws_cmd+=(--metadata "source=locize-backup-cli,timestamp=$(date -u +%s),version=$VERSION")
        aws_cmd+=(--quiet)

        # Add endpoint URL if specified (for MinIO testing)
        if [[ -n "${AWS_ENDPOINT_URL:-}" ]]; then
            aws_cmd+=(--endpoint-url "$AWS_ENDPOINT_URL")
        fi

        if "${aws_cmd[@]}"; then

            log_debug "Uploaded to S3: $(basename "$s3_key")"
            return 0
        else
            log_warn "S3 upload failed (attempt $attempt/$MAX_RETRIES): $s3_key"
        fi

        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_debug "Waiting ${RETRY_DELAY}s before retry..."
            sleep "$RETRY_DELAY"
        fi

        ((attempt++))
    done

    log_error "Failed to upload to S3 after $MAX_RETRIES attempts: $s3_key"
    return 1
}

# Process a single language/namespace combination
process_combination() {
    local language="$1"
    local namespace="$2"
    local daily_dir="$3"
    local timestamp="$4"

    local filename="i18n-$namespace-$language-$timestamp.json"
    local local_file="$daily_dir/$filename"

    log_info "Processing: $language/$namespace"
    log_debug "Downloading $language/$namespace using locize-cli..."

    # Download file using locize-cli
    if ! download_with_locize_cli "$language" "$namespace" "$local_file"; then
        log_error "Failed to download: $language/$namespace"
        return 1
    fi

    log_debug "Download completed for $language/$namespace"

    # Upload to S3 if configured
    if [[ "$USE_S3" == "true" ]]; then
        local s3_key="$(date -u '+%Y/%m/%d')/$filename"
        if ! upload_to_s3 "$local_file" "$s3_key"; then
            log_error "Failed to upload: $language/$namespace"
            return 1
        fi
        log_success "Successfully backed up: $language/$namespace -> s3://$S3_BUCKET/$s3_key"
    else
        log_success "Successfully backed up: $language/$namespace -> $local_file"
    fi

    # Rate limiting
    sleep "$RATE_LIMIT_DELAY"

    return 0
}

run_backup() {
    local timestamp=$(date -u '+%Y%m%d-%H%M%S')
    local daily_dir
    daily_dir=$(setup_backup_dir)

    # Convert comma-separated strings to arrays
    IFS=',' read -ra lang_array <<< "$LANGUAGES"
    IFS=',' read -ra ns_array <<< "$NAMESPACES"

    local total_combinations=$((${#lang_array[@]} * ${#ns_array[@]}))
    local successful=0
    local failed=0
    local failed_combinations=()

    log_info "Starting enhanced backup process with locize-cli"
    log_info "Project ID: $PROJECT_ID"
    log_info "Version: $VERSION"
    log_info "Languages: ${lang_array[*]}"
    log_info "Namespaces: ${ns_array[*]}"
    log_info "Total combinations: $total_combinations"
    if [[ "$USE_S3" == "true" ]]; then
        log_info "Storage: S3 bucket s3://$S3_BUCKET"
    else
        log_info "Storage: Local directory $BACKUP_DIR"
    fi

    # Process all combinations
    for language in "${lang_array[@]}"; do
        for namespace in "${ns_array[@]}"; do
            if process_combination "$language" "$namespace" "$daily_dir" "$timestamp"; then
                successful=$((successful + 1))
            else
                failed=$((failed + 1))
                failed_combinations+=("$language/$namespace")
            fi
        done
    done

    # Summary
    log_info "Backup process completed"
    log_info "Total: $total_combinations, Successful: $successful, Failed: $failed"

    if [[ $failed -gt 0 ]]; then
        log_error "Failed combinations:"
        printf '%s\n' "${failed_combinations[@]}" >&2
    fi

    # Cleanup local files if requested
    if [[ "$CLEANUP_LOCAL_FILES" == "true" && $successful -gt 0 ]]; then
        log_info "Cleaning up local files..."
        # Only clean up the daily directory, keep summaries
        rm -rf "$daily_dir"
        log_debug "Local backup files cleaned up (summaries preserved)"
    fi

    # Create summary file for monitoring
    create_summary_report "$timestamp" "$total_combinations" "$successful" "$failed" "${failed_combinations[@]}"

    # Exit with appropriate code
    if [[ $failed -gt 0 ]]; then
        log_error "Backup completed with failures"
        exit 1
    else
        log_success "Backup completed successfully"
        exit 0
    fi
}

# Create summary report for monitoring
create_summary_report() {
    local timestamp="$1"
    local total="$2"
    local successful="$3"
    local failed="$4"
    shift 4
    local failed_combinations=("$@")

    # Create summary file in summaries directory to match legacy structure
    local summary_file="$BACKUP_DIR/summaries/backup-summary-$timestamp.json"

    # Create summary JSON with storage-specific information
    if [[ "$USE_S3" == "true" ]]; then
        cat > "$summary_file" << EOF
{
  "timestamp": "$timestamp",
  "project_id": "$PROJECT_ID",
  "version": "$VERSION",
  "backup_date": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
  "total_combinations": $total,
  "successful": $successful,
  "failed": $failed,
  "success_rate": $(echo "scale=2; $successful * 100 / $total" | bc -l 2>/dev/null || echo "0"),
  "failed_combinations": $(printf '%s\n' "${failed_combinations[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
  "storage_type": "s3",
  "s3_bucket": "$S3_BUCKET",
  "backup_method": "locize-cli",
  "cli_version": "$(locize --version 2>/dev/null || echo 'unknown')"
}
EOF
    else
        cat > "$summary_file" << EOF
{
  "timestamp": "$timestamp",
  "project_id": "$PROJECT_ID",
  "version": "$VERSION",
  "backup_date": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
  "total_combinations": $total,
  "successful": $successful,
  "failed": $failed,
  "success_rate": $(echo "scale=2; $successful * 100 / $total" | bc -l 2>/dev/null || echo "0"),
  "failed_combinations": $(printf '%s\n' "${failed_combinations[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
  "storage_type": "local",
  "local_backup_path": "$BACKUP_DIR",
  "backup_method": "locize-cli",
  "cli_version": "$(locize --version 2>/dev/null || echo 'unknown')"
}
EOF
    fi

    # Upload summary to S3 if using S3 storage
    if [[ "$USE_S3" == "true" ]]; then
        local s3_summary_key="summaries/backup-summary-$timestamp.json"
        if upload_to_s3 "$summary_file" "$s3_summary_key"; then
            log_success "Summary report uploaded: s3://$S3_BUCKET/$s3_summary_key"
        else
            log_warn "Failed to upload summary report"
        fi
    else
        log_success "Summary report created: $summary_file"
    fi

    # Cleanup summary file if requested and using S3 (keep local summaries for local storage)
    if [[ "$CLEANUP_LOCAL_FILES" == "true" && "$USE_S3" == "true" ]]; then
        rm -f "$summary_file"
    fi
}

cleanup_on_exit() {
    local exit_code=$?
    log_info "Script exiting with code: $exit_code"

    # Cleanup any temporary files (but preserve summaries directory structure)
    if [[ -n "${BACKUP_DIR:-}" && "$CLEANUP_LOCAL_FILES" == "true" ]]; then
        log_debug "Cleaning up temporary files..."
        # Only clean up date-based directories, preserve summaries
        find "$BACKUP_DIR" -type d -name "[0-9][0-9][0-9][0-9]" -exec rm -rf {} + 2>/dev/null || true
    fi

    exit $exit_code
}

trap cleanup_on_exit EXIT
trap 'log_error "Script interrupted"; exit 130' INT TERM

main() {
    # Parse command line arguments first
    parse_arguments "$@"

    log_info "=== Locize Backup Script Started ==="
    log_info "Version: 1.0.0"
    log_info "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

    # Validate environment
    check_dependencies
    validate_config

    # Check if backup was run recently (unless forced)
    check_last_backup_time

    # Run backup
    run_backup
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi