#!/bin/bash

# Version Manager for Raphael Kernel and RootFS
# This script manages version tagging and release coordination

set -e

# Default configuration
KERNEL_VERSION="6.17"
RELEASE_TAG="v6.17"
DISTRIBUTION="ubuntu"
DESKTOP_ENVIRONMENT="none"
KERNEL_SOURCE="release"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --kernel-version VERSION    Kernel version (default: $KERNEL_VERSION)"
    echo "  --release-tag TAG          Release tag (default: $RELEASE_TAG)"
    echo "  --distribution DIST        Distribution: ubuntu|armbian (default: $DISTRIBUTION)"
    echo "  --desktop-env ENV          Desktop environment (default: $DESKTOP_ENVIRONMENT)"
    echo "  --kernel-source SOURCE     Kernel source: release|artifacts (default: $KERNEL_SOURCE)"
    echo "  --build-kernel             Trigger kernel build workflow"
    echo "  --build-rootfs             Trigger rootfs build workflow"
    echo "  --build-all                Trigger both kernel and rootfs builds"
    echo "  --list-releases            List available releases"
    echo "  --check-version            Check if version exists in releases"
    echo "  --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --build-kernel --kernel-version 6.1.80 --release-tag v6.1.80"
    echo "  $0 --build-rootfs --kernel-version 6.1.80 --distribution ubuntu"
    echo "  $0 --build-all --kernel-version 6.2.0 --release-tag v6.2.0"
}

# Function to trigger kernel build workflow
trigger_kernel_build() {
    echo "🚀 Triggering kernel build workflow..."
    echo "   Kernel Version: $KERNEL_VERSION"
    echo "   Release Tag: $RELEASE_TAG"
    
    gh workflow run kernel-build.yml \
        -f kernel_version="$KERNEL_VERSION" \
        -f release_tag="$RELEASE_TAG" \
        -f upload_to_release=true
    
    echo "✅ Kernel build workflow triggered successfully"
    echo "📊 Monitor progress at: https://github.com/$GITHUB_REPOSITORY/actions"
}

# Function to trigger rootfs build workflow
trigger_rootfs_build() {
    echo "🚀 Triggering rootfs build workflow..."
    echo "   Distribution: $DISTRIBUTION"
    echo "   Kernel Version: $KERNEL_VERSION"
    echo "   Kernel Source: $KERNEL_SOURCE"
    echo "   Release Tag: $RELEASE_TAG"
    echo "   Desktop Environment: $DESKTOP_ENVIRONMENT"
    
    gh workflow run main.yml \
        -f kernel_version="$KERNEL_VERSION" \
        -f distribution="$DISTRIBUTION" \
        -f kernel_source="$KERNEL_SOURCE" \
        -f release_tag="$RELEASE_TAG" \
        -f desktop_environment="$DESKTOP_ENVIRONMENT"
    
    echo "✅ RootFS build workflow triggered successfully"
    echo "📊 Monitor progress at: https://github.com/$GITHUB_REPOSITORY/actions"
}

# Function to trigger both builds
trigger_all_builds() {
    echo "🏗️  Triggering complete build pipeline..."
    
    # First build kernel
    trigger_kernel_build
    
    echo ""
    echo "⏳ Waiting for kernel build to complete..."
    
    # Then build rootfs
    trigger_rootfs_build
    
    echo ""
    echo "🎉 Complete build pipeline triggered!"
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --kernel-version)
                KERNEL_VERSION="$2"
                shift 2
                ;;
            --release-tag)
                RELEASE_TAG="$2"
                shift 2
                ;;
            --distribution)
                DISTRIBUTION="$2"
                shift 2
                ;;
            --desktop-env)
                DESKTOP_ENVIRONMENT="$2"
                shift 2
                ;;
            --kernel-source)
                KERNEL_SOURCE="$2"
                shift 2
                ;;
            --build-kernel)
                BUILD_KERNEL=true
                shift
                ;;
            --build-rootfs)
                BUILD_ROOTFS=true
                shift
                ;;
            --build-all)
                BUILD_ALL=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "❌ Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set GitHub repository context
    if [[ -z "$GITHUB_REPOSITORY" ]]; then
        GITHUB_REPOSITORY=$(git remote get-url origin | sed 's|.*github.com/||' | sed 's/\.git$//')
        if [[ -z "$GITHUB_REPOSITORY" ]]; then
            echo "❌ Could not determine GitHub repository"
            echo "   Please set GITHUB_REPOSITORY environment variable"
            exit 1
        fi
    fi
    
    # Execute requested actions
    if [[ "$LIST_RELEASES" == "true" ]]; then
        list_releases
    elif [[ "$CHECK_VERSION" == "true" ]]; then
        check_release_exists "$RELEASE_TAG"
        check_version_compatibility "$KERNEL_VERSION" "$DISTRIBUTION"
    elif [[ "$BUILD_ALL" == "true" ]]; then
        trigger_all_builds
    elif [[ "$BUILD_KERNEL" == "true" ]]; then
        trigger_kernel_build
    elif [[ "$BUILD_ROOTFS" == "true" ]]; then
        trigger_rootfs_build
    else
        echo "ℹ️  No action specified. Use --help for usage information."
        usage
    fi
}

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed"
    echo "   Please install it from: https://cli.github.com/"
    exit 1
fi

# Check if authenticated with GitHub
if ! gh auth status &>/dev/null; then
    echo "❌ Not authenticated with GitHub"
    echo "   Please run: gh auth login"
    exit 1
fi

# Run main function
main "$@"