#!/bin/bash
#
# Build minimal BusyBox static binary for E2B sandbox systeminit.
# Produces a stripped, musl-linked binary with only the applets needed
# for VM initialization (mount, init, switch_root, etc.)
#
# Usage:
#   sudo ./build.sh                          # build for host arch
#   sudo TARGET_ARCH=arm64 ./build.sh        # build for arm64
#   sudo BUSYBOX_VERSION=1.37.0 ./build.sh   # custom version
#
# Output: builds/{version}/{arch}/busybox

set -euo pipefail

BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
HOST_ARCH="$(uname -m)"

# Normalize to Go arch convention for output dir
case "$TARGET_ARCH" in
  x86_64|amd64)   NATIVE_ARCH="x86_64"; GO_ARCH="amd64" ;;
  aarch64|arm64)   NATIVE_ARCH="aarch64"; GO_ARCH="arm64" ;;
  *) echo "ERROR: Unsupported arch: $TARGET_ARCH"; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/builds/${BUSYBOX_VERSION}/${GO_ARCH}"

echo "=== Building BusyBox ${BUSYBOX_VERSION} for ${GO_ARCH} (${NATIVE_ARCH}) ==="

# ── Dependencies ──────────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq build-essential musl-tools linux-headers-generic curl bzip2 >/dev/null

# ── Download source ───────────────────────────────────────────────────────────
SRCDIR="/tmp/busybox-src-${BUSYBOX_VERSION}-${GO_ARCH}"
if [ ! -d "$SRCDIR" ]; then
  echo "Downloading BusyBox ${BUSYBOX_VERSION}..."
  curl -sL "https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2" | tar xj -C /tmp
  mv "/tmp/busybox-${BUSYBOX_VERSION}" "$SRCDIR"
fi

cd "$SRCDIR"
make distclean 2>/dev/null || true

# ── Configure ─────────────────────────────────────────────────────────────────
make allnoconfig

# Enable only the applets needed for E2B sandbox systeminit
APPLETS=(
  ARCH BASE64 BASENAME BUSYBOX CHATTR CHMOD CHOWN CHROOT CLEAR
  DATE DIRNAME DMESG ECHO EXPR FALSE FIND GREP HALT HEAD HOSTNAME
  INIT KILL LSATTR MKDIR MKNOD MKTEMP MOUNT PIVOT_ROOT POWEROFF
  READLINK REBOOT RMDIR SLEEP SORT STAT STTY SWITCH_ROOT SYNC
  TAIL TEST TOUCH TRUE UMOUNT UNAME UNIQ XARGS
)

for applet in "${APPLETS[@]}"; do
  sed -i "s/# CONFIG_${applet} is not set/CONFIG_${applet}=y/" .config
done

cat >> .config <<'EOF'
CONFIG_STATIC=y
CONFIG_FEATURE_SH_STANDALONE=y
CONFIG_FEATURE_PREFER_APPLETS=y
CONFIG_FEATURE_INIT_SYSLOG=y
CONFIG_FEATURE_MOUNT_FLAGS=y
CONFIG_FEATURE_MOUNT_LOOP=y
CONFIG_FEATURE_MOUNT_HELPERS=y
CONFIG_FEATURE_FSTAB_GENERATION=y
CONFIG_FEATURE_PIDFILE=y
CONFIG_FEATURE_SYSLOG=y
EOF

# ── Build ─────────────────────────────────────────────────────────────────────
# Native build on matching arch — use musl-gcc for static musl linking
CC="musl-gcc"
MAKE_OPTS=""

make oldconfig CC="$CC" HOSTCC=gcc < /dev/null
echo "Building ($(nproc) jobs)..."
make -j"$(nproc)" CC="$CC" HOSTCC=gcc
strip busybox

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Result ==="
file busybox
APPLET_COUNT=$(./busybox --list | wc -l)
BINARY_SIZE=$(stat -c%s busybox)
echo "Applets: ${APPLET_COUNT}"
echo "Size: ${BINARY_SIZE} bytes ($(( BINARY_SIZE / 1024 )) KB)"
./busybox --list | sort | tr '\n' ' '
echo ""

# ── Output ────────────────────────────────────────────────────────────────────
mkdir -p "$BUILD_DIR"
cp busybox "$BUILD_DIR/busybox"
echo ""
echo "Output: ${BUILD_DIR}/busybox"
