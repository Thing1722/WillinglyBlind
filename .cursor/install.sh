#!/usr/bin/env bash
#
# Cloud Agent install script for WillinglyBlind.
#
# WillinglyBlind is a LiDAR-based obstacle detection + warning system that
# ultimately targets iOS (ARKit/Xcode). The full iOS app can only be built and
# run on macOS with Xcode and a LiDAR-equipped device, which a Linux Cloud Agent
# cannot provide. This script installs the Swift toolchain for Linux so that
# platform-independent Swift code (core logic, packages, unit tests) can be
# built and tested here and in CI.
#
# The script is idempotent: it can be run repeatedly and against cached state.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# 1. System packages required by the Swift toolchain on Ubuntu 24.04.
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  binutils \
  git \
  gnupg2 \
  libc6-dev \
  libcurl4-openssl-dev \
  libedit2 \
  libgcc-s1 \
  libgcc-12-dev \
  libncurses-dev \
  libpython3-dev \
  libsqlite3-0 \
  libstdc++-13-dev \
  libxml2-dev \
  libz3-dev \
  pkg-config \
  tzdata \
  unzip \
  zlib1g-dev

# 2. Install swiftly (the official Swift toolchain manager) plus the default
#    Swift release, unless a working toolchain is already present.
SWIFTLY_HOME="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}"
SWIFTLY_ENV="$SWIFTLY_HOME/env.sh"

if [ ! -f "$SWIFTLY_ENV" ]; then
  ARCH="$(uname -m)"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  curl -fsSL -o "$TMP_DIR/swiftly.tar.gz" \
    "https://download.swift.org/swiftly/linux/swiftly-$ARCH.tar.gz"
  tar -xzf "$TMP_DIR/swiftly.tar.gz" -C "$TMP_DIR"
  "$TMP_DIR/swiftly" init --assume-yes --quiet-shell-followup
fi

# 3. Make the toolchain available to this shell and to future login shells.
# shellcheck disable=SC1090
. "$SWIFTLY_ENV"

if ! grep -qs 'swiftly/env.sh' "$HOME/.bashrc" 2>/dev/null; then
  {
    printf '\n# Added by WillinglyBlind Cloud Agent setup\n'
    printf '[ -f "%s" ] && . "%s"\n' "$SWIFTLY_ENV" "$SWIFTLY_ENV"
  } >> "$HOME/.bashrc"
fi

# 4. Report the resolved toolchain for setup logs.
swift --version
