#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Local Docker Isolated Build & Test Harness
# Limits CPU usage to 8 cores (half of host 16 cores) and saves failure logs to logs/local_build_failures/

set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL_LOG_DIR="$PROJ_ROOT/logs/local_build_failures"
mkdir -p "$FAIL_LOG_DIR"

TARGET_NAME="${1:-JDC-ATHENA}"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="$FAIL_LOG_DIR/failure_local_${TARGET_NAME}_${TIMESTAMP}.log"

echo "=========================================================="
echo " Starting Isolated Local Docker Full Build Test ($TARGET_NAME)"
echo " Target Architecture: Qualcomm IPQ60xx ARM64 (aarch64_cortex-a53)"
echo " CPU Limit: 8 Cores (Half of Host 16 Cores)"
echo " Failure Log Output: $LOG_FILE"
echo "=========================================================="

BUILD_WORK_DIR="$PROJ_ROOT/.temp_build_source/local_docker_wrt"
mkdir -p "$BUILD_WORK_DIR"

# Use pre-built image if available, otherwise fall back to ubuntu:22.04
BUILDER_IMAGE="openwrt-builder:local"
if ! docker image inspect "$BUILDER_IMAGE" &>/dev/null; then
    echo "Pre-built image not found, using ubuntu:22.04 (slower first run)..."
    BUILDER_IMAGE="ubuntu:22.04"
fi

# Step 1: Run build inside Docker container with --cpus=8 (50% CPU limit & low priority)
docker rm -f openwrt_local_builder 2>/dev/null || true
nice -n 19 ionice -c 3 docker run --rm \
    --name openwrt_local_builder \
    --cpus=8 \
    -v "$PROJ_ROOT:/project" \
    -v "$BUILD_WORK_DIR:/build" \
    -w /build \
    $BUILDER_IMAGE bash -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export FORCE_UNSAFE_CONFIGURE=1
        export GOFLAGS="-buildvcs=false"
        export GOPROXY="https://goproxy.cn,https://goproxy.io,direct"
        export GONOSUMCHECK="*"
        git config --global --add safe.directory "*"

        # Check if pre-built image (skip apt) or base ubuntu (need apt)
        if ! command -v ccache &>/dev/null; then
            echo "=== Installing OpenWRT Build Dependencies in Container ==="
            apt-get update -qq
            apt-get install -y -qq \
                build-essential clang llvm lld flex bison gawk gettext git libncurses-dev \
                libssl-dev python3 python3-setuptools python3-dev python3-pip python3-distutils \
                rsync unzip zlib1g-dev file wget subversion swig time \
                curl ccache sudo patch cmake libgmp-dev libmpfr-dev libmpc-dev
        else
            echo "=== Build dependencies already installed (pre-built image) ==="
        fi

        echo "=== Preparing OpenWRT Source Code ==="
        if [ ! -d "/build/.git" ]; then
            echo "Cloning VIKINGYFY/immortalwrt..."
            git clone --depth 1 -b main https://github.com/VIKINGYFY/immortalwrt.git /build
        else
            echo "Using existing /build repo..."
        fi

        echo "=== Updating & Installing Feeds ==="
        if [ ! -d "/build/feeds/packages" ]; then
            /build/scripts/feeds update -a
            /build/scripts/feeds install -a
        else
            echo "Feeds already initialized, skipping feeds update."
        fi

        echo "=== Running Custom Packages & Handles Scripts ==="
        cd /build/package
        bash /project/Scripts/Packages.sh
        bash /project/Scripts/Handles.sh

        echo "=== Configuring Target & Running Settings Script ==="
        cd /build
        TARGET_NAME="${1:-JDC-ATHENA}"
        export WRT_CONFIG="$TARGET_NAME"
        export WRT_THEME="aurora"
        export WRT_NAME="JDC-Athena"
        export WRT_SSID="JDC-Athena"
        export WRT_WORD="12345678"
        export WRT_IP="192.168.10.1"
        export WRT_MARK="ImmortalWrt"
        export WRT_DATE="$(date +%Y.%m.%d)"

        cat /project/Config/GENERAL.txt > /build/.config
        cat /project/Config/${TARGET_NAME}.txt >> /build/.config
        bash /project/Scripts/Settings.sh
        make defconfig

        echo "=== Restoring Offline Tarball Cache from .dl_cache ==="
        mkdir -p /build/dl /project/.dl_cache
        if [ -d "/project/.dl_cache" ]; then
            cp -rn /project/.dl_cache/* /build/dl/ 2>/dev/null || true
        fi

        echo "=== Downloading Package Sources ==="
        make download -j8 || true
        cp -rn /build/dl/* /project/.dl_cache/ 2>/dev/null || true

        echo "=== Starting Full Firmware Compilation (8 Cores) ==="
        make -j8 V=s
        cp -rn /build/dl/* /project/.dl_cache/ 2>/dev/null || true
' > "$LOG_FILE" 2>&1 || {
    EXIT_CODE=$?
    echo "=========================================================="
    echo " LOCAL DOCKER BUILD FAILED! (Exit Code: $EXIT_CODE)"
    echo " Log saved to: $LOG_FILE"
    echo "=========================================================="
    exit $EXIT_CODE
}

echo "=========================================================="
echo " LOCAL DOCKER BUILD SUCCESSFUL!"
echo " Firmware output files in: $BUILD_WORK_DIR/bin/targets/"
echo "=========================================================="
rm -f "$LOG_FILE"  # Clean up log on success
