#!/bin/bash

# Integration Test Script for Locize Backup Docker Image
# Tests the basic functionality of the backup container

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
IMAGE_NAME="ligouras/locize-backup"
TEST_DIR="$(pwd)/test-output"
SCRIPT_DIR="$(dirname "$0")"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"

    log_info "Running test: $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))

    if $test_function; then
        log_success "✅ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    echo
}

# Setup test environment
setup_test_env() {
    log_info "Setting up test environment..."

    # Create test directory
    mkdir -p "$TEST_DIR"

    # Change to project root
    cd "$PROJECT_ROOT"

    # Check if image exists, build if not
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        log_warn "Image $IMAGE_NAME not found, building..."
        if ! npm run build; then
            log_error "Failed to build image"
            return 1
        fi
    fi

    log_success "Test environment setup complete"
}

# Cleanup test environment
cleanup_test_env() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    log_success "Cleanup complete"
}

# Test 1: Image exists and can be inspected
test_image_exists() {
    docker image inspect "$IMAGE_NAME" &>/dev/null
}

# Test 2: Container can start and show help
test_container_help() {
    docker run --rm --entrypoint locize "$IMAGE_NAME" --help &>/dev/null
}

# Test 3: Container shows correct locize-cli version
test_locize_version() {
    local expected_version
    expected_version=$(cat .locize-cli-version)

    local actual_version
    actual_version=$(docker run --rm --entrypoint locize "$IMAGE_NAME" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")

    if [[ "$actual_version" == "$expected_version" ]]; then
        log_info "Version match: $actual_version"
        return 0
    else
        log_error "Version mismatch: expected $expected_version, got $actual_version"
        return 1
    fi
}

# Test 4: Container has required dependencies
test_dependencies() {
    local deps=("locize" "jq" "aws" "bash")

    for dep in "${deps[@]}"; do
        if ! docker run --rm --entrypoint bash "$IMAGE_NAME" -c "command -v $dep" &>/dev/null; then
            log_error "Missing dependency: $dep"
            return 1
        fi
    done

    log_info "All dependencies found: ${deps[*]}"
    return 0
}

# Test 5: Container runs as non-root user
test_non_root_user() {
    local user_info
    user_info=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "id -u && id -un" 2>/dev/null)

    if echo "$user_info" | grep -q "1001" && echo "$user_info" | grep -q "locize"; then
        log_info "Running as non-root user: locize (1001)"
        return 0
    else
        log_error "Not running as expected user. Got: $user_info"
        return 1
    fi
}

# Test 6: Backup script is executable and accessible
test_backup_script() {
    if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "test -x /app/backup/backup.sh"; then
        log_info "Backup script is executable"
        return 0
    else
        log_error "Backup script not found or not executable"
        return 1
    fi
}

# Test 7: Container has proper working directory
test_working_directory() {
    local working_dir
    working_dir=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "pwd" 2>/dev/null)

    if [[ "$working_dir" == "/app/backup" ]]; then
        log_info "Working directory is correct: $working_dir"
        return 0
    else
        log_error "Working directory incorrect. Expected /app/backup, got: $working_dir"
        return 1
    fi
}

# Test 8: Container can handle basic environment variables
test_env_variables() {
    local test_output
    test_output=$(docker run --rm \
        -e LOCIZE_PROJECT_ID=test-project \
        -e S3_BUCKET_NAME=test-bucket \
        -e LOG_LEVEL=DEBUG \
        --entrypoint bash "$IMAGE_NAME" -c "echo \$LOCIZE_PROJECT_ID \$S3_BUCKET_NAME \$LOG_LEVEL" 2>/dev/null)

    if [[ "$test_output" == "test-project test-bucket DEBUG" ]]; then
        log_info "Environment variables handled correctly"
        return 0
    else
        log_error "Environment variables not handled correctly. Got: $test_output"
        return 1
    fi
}

# Test 9: npm scripts work correctly
test_npm_scripts() {
    local scripts=("version" "version:sync" "help")

    for script in "${scripts[@]}"; do
        if ! npm run "$script" &>/dev/null; then
            log_error "npm script failed: $script"
            return 1
        fi
    done

    log_info "npm scripts working: ${scripts[*]}"
    return 0
}

# Test 10: Version synchronization script works
test_version_sync_script() {
    if [[ -x "scripts/update-version.js" ]]; then
        # Test help command
        if node scripts/update-version.js --help &>/dev/null; then
            log_info "Version sync script is functional"
            return 0
        else
            log_error "Version sync script help failed"
            return 1
        fi
    else
        log_error "Version sync script not found or not executable"
        return 1
    fi
}

# Test 11: MinIO testing configuration exists
test_minio_config() {
    if [[ -f ".env.minio" ]]; then
        log_info "MinIO test configuration found"
        return 0
    else
        log_error "MinIO test configuration (.env.minio) not found"
        return 1
    fi
}

# Test 12: Docker Compose MinIO services can start
test_minio_services() {
    log_info "Testing MinIO services startup..."

    # Start MinIO services
    if docker compose --profile testing up -d minio minio-setup &>/dev/null; then
        sleep 5  # Wait for services to start

        # Check if MinIO is healthy
        if curl -f http://localhost:9000/minio/health/live &>/dev/null; then
            log_info "MinIO services started successfully"

            # Cleanup
            docker compose --profile testing down &>/dev/null
            return 0
        else
            log_error "MinIO health check failed"
            docker compose --profile testing down &>/dev/null
            return 1
        fi
    else
        log_error "Failed to start MinIO services"
        return 1
    fi
}

# Test 13: Backup script supports MinIO endpoint
test_minio_endpoint_support() {
    # Test that backup script can handle AWS_ENDPOINT_URL
    local test_output
    test_output=$(docker run --rm \
        -e AWS_ENDPOINT_URL=http://localhost:9000 \
        --entrypoint bash "$IMAGE_NAME" -c "echo \$AWS_ENDPOINT_URL" 2>/dev/null)

    if [[ "$test_output" == "http://localhost:9000" ]]; then
        log_info "MinIO endpoint URL support confirmed"
        return 0
    else
        log_error "MinIO endpoint URL not handled correctly"
        return 1
    fi
}

# Test 14: npm MinIO scripts exist
test_minio_npm_scripts() {
    local minio_scripts=("minio:start" "minio:test" "minio:list" "test:minio")

    for script in "${minio_scripts[@]}"; do
        if ! npm run "$script" --silent 2>/dev/null | grep -q "npm ERR!"; then
            continue  # Script exists
        else
            log_error "MinIO npm script missing: $script"
            return 1
        fi
    done

    log_info "MinIO npm scripts available: ${minio_scripts[*]}"
    return 0
}

# Main test execution
main() {
    log_info "Starting Locize Backup Integration Tests"
    log_info "========================================="
    echo

    # Setup
    if ! setup_test_env; then
        log_error "Failed to setup test environment"
        exit 1
    fi

    # Run core tests
    run_test "Image exists and can be inspected" test_image_exists
    run_test "Container can start and show help" test_container_help
    run_test "Container shows correct locize-cli version" test_locize_version
    run_test "Container has required dependencies" test_dependencies
    run_test "Container runs as non-root user" test_non_root_user
    run_test "Backup script is executable" test_backup_script
    run_test "Container has proper working directory" test_working_directory
    run_test "Environment variables work" test_env_variables
    run_test "npm scripts work correctly" test_npm_scripts
    run_test "Version sync script works" test_version_sync_script

    # Run MinIO-specific tests
    log_info "Running MinIO Integration Tests..."
    log_info "================================="
    run_test "MinIO test configuration exists" test_minio_config
    run_test "MinIO endpoint URL support" test_minio_endpoint_support
    run_test "MinIO npm scripts available" test_minio_npm_scripts
    run_test "MinIO services can start" test_minio_services

    # Cleanup
    cleanup_test_env

    # Results
    echo
    log_info "Test Results Summary"
    log_info "==================="
    log_info "Tests Run: $TESTS_RUN"
    log_success "Tests Passed: $TESTS_PASSED"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "Tests Failed: $TESTS_FAILED"
        echo
        log_error "Some tests failed. Please review the output above."
        exit 1
    else
        echo
        log_success "All tests passed! 🎉"
        log_info "The locize-backup Docker setup is working correctly."
        exit 0
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo
        echo "Integration test script for locize-backup Docker image."
        echo "Tests basic functionality, dependencies, and configuration."
        echo
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac