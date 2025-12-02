#!/bin/bash

# Version manager script for Xiaomi K20 Pro (Raphael)
# Standardized implementation with centralized configuration

set -e  # Exit on any error

# ----------------------------- 
# Load centralized configuration
# ----------------------------- 
if [ -f "build-config.sh" ]; then
    source "build-config.sh"
else
    echo "❌ Error: build-config.sh not found!"
    exit 1
fi

# ----------------------------- 
# Color output functions
# ----------------------------- 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ----------------------------- 
# Cleanup function
# ----------------------------- 
cleanup() {
    log_info "Cleaning up..."
    
    # Clean up any temporary files if needed
    rm -f "$TEMP_FILE" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# ----------------------------- 
# Error handling setup
# ----------------------------- 
trap cleanup EXIT

# ----------------------------- 
# GitHub context setup
# ----------------------------- 
setup_github_context() {
    log_info "Setting up GitHub context..."
    
    # Check if running in GitHub Actions
    if [ "$GITHUB_ACTIONS" = "true" ]; then
        log_info "Running in GitHub Actions environment"
        
        # Set GitHub repository from environment
        GITHUB_REPOSITORY="$GITHUB_REPOSITORY"
    else
        log_info "Running in local environment"
        
        # Check if github CLI is installed
        if ! command -v gh >/dev/null 2>&1; then
            log_error "GitHub CLI (gh) is not installed!"
            log_info "Please install it using: sudo apt install gh"
            exit 1
        fi
        
        # Set GitHub repository from current directory
        GITHUB_REPOSITORY="$(gh repo view --json nameWithOwner --template '{{.nameWithOwner}}')"
    fi
    
    log_info "GitHub Repository: $GITHUB_REPOSITORY"
    log_success "GitHub context set up successfully"
    
    # Export for use in other functions
    export GITHUB_REPOSITORY
}

# ----------------------------- 
# Parameter parsing
# ----------------------------- 
parse_arguments() {
    log_info "Parsing command-line arguments..."
    
    # Set default values from environment variables or centralized configuration
    KERNEL_VERSION="${KERNEL_VERSION:-${KERNEL_VERSION_DEFAULT}}"
    RELEASE_TAG="${RELEASE_TAG:-${RELEASE_TAG_DEFAULT}}"
    SKIP_KERNEL="${SKIP_KERNEL:-false}"
    SKIP_ROOTFS="${SKIP_ROOTFS:-false}"
    FULL_BUILD="${FULL_BUILD:-false}"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kernel-version)
                KERNEL_VERSION="$2"
                shift 2
                ;;
            -t|--release-tag)
                RELEASE_TAG="$2"
                shift 2
                ;;
            --skip-kernel)
                SKIP_KERNEL=true
                shift
                ;;
            --skip-rootfs)
                SKIP_ROOTFS=true
                shift
                ;;
            --full-build)
                FULL_BUILD=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # If full build, enable all build steps
    if [ "$FULL_BUILD" = true ]; then
        SKIP_KERNEL=false
        SKIP_ROOTFS=false
    fi
    
    log_success "Arguments parsed successfully"
    log_info "Kernel version: $KERNEL_VERSION"
    log_info "Release tag: $RELEASE_TAG"
    log_info "Skip kernel build: $SKIP_KERNEL"
    log_info "Skip rootfs build: $SKIP_ROOTFS"
}

# ----------------------------- 
# Show help information
# ----------------------------- 
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Manage versions and trigger builds for Xiaomi K20 Pro (Raphael)

OPTIONS:
    -k, --kernel-version VERSION    Kernel version (e.g., 6.18) [default: ${KERNEL_VERSION_DEFAULT}]
    -t, --release-tag TAG            Release tag (e.g., v6.18) [default: ${RELEASE_TAG_DEFAULT}]
    --skip-kernel                    Skip kernel build
    --skip-rootfs                    Skip rootfs build
    --full-build                     Perform full build (kernel + rootfs)
    -h, --help                       Show this help message

EXAMPLES:
    $0 --kernel-version 6.18 --release-tag v6.18
    $0 --full-build
    $0 --skip-kernel
EOF
}

# ----------------------------- 
# Validate parameters
# ----------------------------- 
validate_parameters() {
    log_info "Validating parameters..."
    
    # Validate kernel version format
    validate_kernel_version "$KERNEL_VERSION" || {
        log_error "Invalid kernel version format"
        exit 1
    }
    
    # Validate release tag format
    if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid release tag format. Expected format: vX.Y"
        log_info "Example: v6.18"
        exit 1
    fi
    
    # Validate that at least one build step is enabled
    if [ "$SKIP_KERNEL" = true ] && [ "$SKIP_ROOTFS" = true ]; then
        log_error "Both kernel and rootfs builds are skipped. Nothing to do!"
        exit 1
    fi
    
    log_success "Parameters validated successfully"
}

# ----------------------------- 
# Check dependencies
# ----------------------------- 
check_dependencies() {
    log_info "Checking dependencies..."
    
    # Use centralized dependency check function
    if dependency_check_version_manager; then
        log_success "All dependencies are already installed"
        return 0
    else
        log_warning "Missing dependencies, installing them..."
        install_dependencies
        return $?
    fi
}

# ----------------------------- 
# Install dependencies
# ----------------------------- 
install_dependencies() {
    log_info "Installing dependencies..."
    
    # Update package list
    sudo apt update
    
    # Install required packages
    sudo apt install -y \
        gh \
        curl \
        jq
    
    # Verify GitHub CLI is installed
    if ! command -v gh >/dev/null 2>&1; then
        log_error "Failed to install GitHub CLI (gh)"
        exit 1
    fi
    
    # Verify jq is installed
    if ! command -v jq >/dev/null 2>&1; then
        log_error "Failed to install jq"
        exit 1
    fi
    
    log_success "Dependencies installed successfully"
}

# ----------------------------- 
# Trigger kernel build workflow
# ----------------------------- 
trigger_kernel_build() {
    log_info "Triggering kernel build workflow..."
    
    local kernel_branch="${KERNEL_BRANCH_PREFIX}${KERNEL_VERSION}"
    local workflow_id="kernel-build.yml"
    
    # Check if branch exists
    if ! git ls-remote --exit-code --heads "$KERNEL_REPO" "$kernel_branch" >/dev/null 2>&1; then
        log_error "Kernel branch '$kernel_branch' does not exist in $KERNEL_REPO"
        exit 1
    fi
    
    log_info "Kernel branch: $kernel_branch"
    log_info "Workflow ID: $workflow_id"
    
    # Trigger workflow
    if [ "$GITHUB_ACTIONS" = "true" ]; then
        log_info "Cannot trigger workflows from within GitHub Actions"
        log_info "Kernel build would be triggered in production mode"
    else
        # Use GitHub CLI to trigger workflow
        gh workflow run "$workflow_id" \
            --repo "$GITHUB_REPOSITORY" \
            -f kernel_version="$KERNEL_VERSION" \
            -f release_tag="$RELEASE_TAG"
        
        if [ $? -ne 0 ]; then
            log_error "Failed to trigger kernel build workflow"
            exit 1
        fi
        
        log_success "Kernel build workflow triggered successfully"
    fi
}

# ----------------------------- 
# Trigger rootfs build workflow
# ----------------------------- 
trigger_rootfs_build() {
    log_info "Triggering rootfs build workflow..."
    
    local workflow_id="main.yml"
    
    log_info "Workflow ID: $workflow_id"
    
    # Trigger workflow
    if [ "$GITHUB_ACTIONS" = "true" ]; then
        log_info "Cannot trigger workflows from within GitHub Actions"
        log_info "Rootfs build would be triggered in production mode"
    else
        # Use GitHub CLI to trigger workflow
        gh workflow run "$workflow_id" \
            --repo "$GITHUB_REPOSITORY" \
            -f kernel_version="$KERNEL_VERSION" \
            -f release_tag="$RELEASE_TAG"
        
        if [ $? -ne 0 ]; then
            log_error "Failed to trigger rootfs build workflow"
            exit 1
        fi
        
        log_success "Rootfs build workflow triggered successfully"
    fi
}

# ----------------------------- 
# Trigger full build flow
# ----------------------------- 
trigger_full_build() {
    log_info "Triggering full build flow..."
    
    # Trigger kernel build first
    if [ "$SKIP_KERNEL" != true ]; then
        trigger_kernel_build
        
        # Add a delay to allow kernel build to start
        log_info "Waiting 30 seconds before triggering rootfs build..."
        sleep 30
    fi
    
    # Trigger rootfs build
    if [ "$SKIP_ROOTFS" != true ]; then
        trigger_rootfs_build
    fi
    
    log_success "Full build flow triggered successfully"
}

# ----------------------------- 
# Main function
# ----------------------------- 
main() {
    log_info "Starting version manager for Xiaomi K20 Pro (Raphael)"
    
    # Step 1: Set up GitHub context
    setup_github_context
    
    # Step 2: Parse command-line arguments
    parse_arguments "$@"
    
    # Step 3: Validate parameters
    validate_parameters
    
    # Step 4: Check and install dependencies
    check_dependencies
    
    # Step 5: Trigger appropriate builds
    trigger_full_build
    
    # Step 6: Show completion message
    log_success "All requested builds have been triggered successfully!"
    
    # Show summary
    echo -e "\n📋 Build Summary:"
    echo -e "- Kernel Version: ${BLUE}$KERNEL_VERSION${NC}"
    echo -e "- Release Tag: ${BLUE}$RELEASE_TAG${NC}"
    echo -e "- Kernel Build: ${GREEN}$([ "$SKIP_KERNEL" = true ] && echo "Skipped" || echo "Triggered")${NC}"
    echo -e "- Rootfs Build: ${GREEN}$([ "$SKIP_ROOTFS" = true ] && echo "Skipped" || echo "Triggered")${NC}"
}

# ----------------------------- 
# Script execution
# ----------------------------- 
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi