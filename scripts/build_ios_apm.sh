#!/bin/bash
# Build the WebRTC Audio Processing Module static library for iOS arm64.
#
# Usage: ./scripts/build_ios_apm.sh
#
# Prerequisites: cmake, Xcode with iOS SDK
#
# Output: ios/Libs/libwebrtc_apm_wrapper.a + ios/Libs/include/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_ROOT/android/src/main/cpp/webrtc-audio-processing"
BUILD_DIR="/tmp/webrtc_apm_ios_build"
OUTPUT_DIR="$REPO_ROOT/ios/Libs"

echo "=== Building WebRTC APM for iOS arm64 ==="
echo "Source: $SRC_DIR"
echo "Build:  $BUILD_DIR"
echo "Output: $OUTPUT_DIR"

# Clean previous build.
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Configure with CMake for iOS arm64.
cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_EXAMPLE=OFF

# Build.
cmake --build "$BUILD_DIR" --config Release --parallel "$(sysctl -n hw.ncpu)"

# Merge all static libraries into one (APM + abseil dependencies).
mkdir -p "$OUTPUT_DIR"
LIBS=$(find "$BUILD_DIR" -name '*.a' -type f)
echo "Merging static libraries:"
echo "$LIBS" | while read -r lib; do echo "  $(basename "$lib")"; done

libtool -static -o "$OUTPUT_DIR/libwebrtc_apm_wrapper.a" $LIBS

# Copy headers.
rm -rf "$OUTPUT_DIR/include"
mkdir -p "$OUTPUT_DIR/include"

# WebRTC headers.
rsync -a --include='*/' --include='*.h' --exclude='*' \
  "$SRC_DIR/webrtc/" "$OUTPUT_DIR/include/webrtc/"

# Abseil headers.
rsync -a --include='*/' --include='*.h' --include='*.inc' --exclude='*' \
  "$SRC_DIR/abseil-cpp/absl/" "$OUTPUT_DIR/include/absl/"

# Verify.
echo ""
echo "=== Build complete ==="
file "$OUTPUT_DIR/libwebrtc_apm_wrapper.a"
lipo -info "$OUTPUT_DIR/libwebrtc_apm_wrapper.a"
echo "Headers: $(find "$OUTPUT_DIR/include" -name '*.h' | wc -l | tr -d ' ') files"
