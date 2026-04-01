# fc-busybox

Minimal BusyBox static builds for [E2B](https://e2b.dev) sandbox systeminit.

## What this builds

A stripped-down BusyBox binary with only the applets needed for sandbox VM initialization, statically linked with musl libc for both **amd64** and **arm64**.

### Applets

```
arch base64 basename busybox chattr chmod chown chroot clear date dirname
dmesg echo expr false find grep halt head hostname init kill lsattr mkdir
mknod mktemp mount pivot_root poweroff readlink reboot rmdir sleep sort
stat stty switch_root sync tail test touch true umount uname uniq xargs
```

## Usage

### GitHub Actions (recommended)

1. Go to [Actions > Build BusyBox](../../actions/workflows/build.yml)
2. Click **Run workflow**, enter the BusyBox version (default: `1.36.1`)
3. Download binaries from the GitHub Release

### Local build

```bash
# Native build
sudo ./build.sh

# Cross-compile for arm64
sudo TARGET_ARCH=arm64 ./build.sh

# Custom version
sudo BUSYBOX_VERSION=1.37.0 ./build.sh
```

Output: `builds/{version}/{arch}/busybox`