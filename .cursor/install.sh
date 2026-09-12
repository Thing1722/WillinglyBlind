#!/usr/bin/env bash
# Idempotent setup for the WillinglyBlind / SafeStep repository on a Linux Cloud Agent.
#
# NOTE ON PLATFORM: SafeStep is a native iOS SwiftUI app. Building and running the
# iOS app itself requires macOS + Xcode (SwiftUI, ARKit/LiDAR, the iOS Simulator),
# none of which exist on a Linux Cloud Agent. This script installs the open-source
# Swift toolchain for Linux so that platform-independent Swift code (logic, Swift
# packages, unit tests, syntax checks) can be compiled and run here. It cannot make
# the iOS UI frameworks available.
set -euo pipefail

SWIFT_VERSION="6.3.3"
SWIFT_DIR="/opt/swift"
SWIFT_BIN="${SWIFT_DIR}/usr/bin"
TARBALL_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"

# Use sudo only when we are not already root (build images often run as root).
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

echo "==> Installing system dependencies for Swift"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq \
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libgcc-13-dev libncurses-dev libpython3-dev libsqlite3-0 \
  libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata \
  zip unzip zlib1g-dev curl ca-certificates

if [ -x "${SWIFT_BIN}/swift" ]; then
  echo "==> Swift already present at ${SWIFT_BIN}, skipping download"
else
  echo "==> Downloading Swift ${SWIFT_VERSION} for Ubuntu 24.04"
  tmp_tarball="$(mktemp /tmp/swift-XXXXXX.tar.gz)"
  curl -fsSL -o "${tmp_tarball}" "${TARBALL_URL}"
  echo "==> Extracting Swift to ${SWIFT_DIR}"
  $SUDO mkdir -p "${SWIFT_DIR}"
  $SUDO tar xzf "${tmp_tarball}" -C "${SWIFT_DIR}" --strip-components=1
  rm -f "${tmp_tarball}"
fi

echo "==> Exposing swift on PATH"
$SUDO ln -sf "${SWIFT_BIN}/swift" /usr/local/bin/swift
$SUDO ln -sf "${SWIFT_BIN}/swiftc" /usr/local/bin/swiftc
echo "export PATH=${SWIFT_BIN}:\$PATH" | $SUDO tee /etc/profile.d/swift.sh >/dev/null
$SUDO chmod +x /etc/profile.d/swift.sh

echo "==> Swift toolchain ready:"
"${SWIFT_BIN}/swift" --version
