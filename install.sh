#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRIVER_COMMIT=6084a1545589beec0c741200b18b0902cca225ba
usage() { echo 'Usage: bash install.sh {prepare|initialize --erase-sensor|build|install|enable-login}'; }
need_root() { [[ $EUID == 0 ]] || { echo 'Run this step with sudo.' >&2; exit 1; }; }
check_host() {
  . /etc/os-release
  [[ $ID == ubuntu && $VERSION_ID == 24.04 && $(dpkg --print-architecture) == amd64 ]] || {
    echo 'Supported target: Ubuntu 24.04 amd64 only.' >&2; exit 1;
  }
  lsusb -d 138a:0090 | grep -q . || { echo 'Reader 138a:0090 not found.' >&2; exit 1; }
}
apply_patch() {
  local target=$1 patchfile=$2
  if patch --batch --forward --dry-run -d "$target" -p1 < "$patchfile" >/dev/null 2>&1; then
    patch --batch --forward -d "$target" -p1 < "$patchfile"
  elif patch --batch --reverse --dry-run -d "$target" -p1 < "$patchfile" >/dev/null 2>&1; then
    echo 'Patch already applied.'
  else
    echo "Patch does not match installed sources: $patchfile" >&2; exit 1
  fi
}
case ${1:-} in
prepare)
  need_root; check_host
  # Mask first: udev can otherwise start the driver during package installation/reset.
  systemctl mask --now python3-validity.service
  apt-get update
  apt-get install software-properties-common patch git meson pkg-config \
    libfprint-2-tod-dev libfprint-2-dev libglib2.0-dev libgusb-dev \
    libpixman-1-dev libssl-dev libnss3-dev libusb-1.0-0-dev
  add-apt-repository -y ppa:uunicorn/open-fprintd
  apt-get update
  apt-get install open-fprintd fprintd-clients python3-validity
  systemctl mask --now python3-validity.service
  backup=$(mktemp -d /var/backups/vfs0090.XXXXXX)
  cp -a /usr/lib/python3/dist-packages/validitysensor/{init_flash.py,usb.py} "$backup/"
  apply_patch /usr/lib/python3/dist-packages "$ROOT/patches/python-validity-294.patch"
  echo "Original Python files backed up to $backup"
  echo 'Next: fully shut down, wait 20 seconds, then power on and run initialize.'
  ;;
initialize)
  need_root; check_host
  [[ ${2:-} == --erase-sensor ]] || {
    echo 'This step clears sensor pairing and may erase Windows/Linux fingerprints.'
    echo 'To proceed, use: sudo bash install.sh initialize --erase-sensor'; exit 1;
  }
  systemctl mask --now python3-validity.service
  validity-sensors-firmware
  python3 /usr/share/python-validity/playground/factory-reset.py
  # Initialize directly while udev-triggered service startup remains blocked.
  # Sensor reboots are expected between partitioning, firmware upload and calibration.
  python3 - <<'PY'
import time
from validitysensor import init
from validitysensor.sensor import RebootException
for attempt in range(5):
    try:
        init.open()
    except RebootException:
        init.usb.close()
        time.sleep(3)
    else:
        init.close()
        print('Sensor initialization completed.')
        break
else:
    raise SystemExit('Initialization did not finish after five sensor reboots. See FAQ.md.')
PY
  ;;
build)
  check_host
  [[ $EUID != 0 ]] || { echo 'Build as your normal user, without sudo.' >&2; exit 1; }
  mkdir -p "$ROOT/build"
  src="$ROOT/build/driver-source"
  if [[ ! -d $src/.git ]]; then
    git clone https://github.com/rabbitambulance-ra/libfprint-tod-vfs0090.git "$src"
  fi
  [[ $(git -C "$src" rev-parse HEAD) == "$DRIVER_COMMIT" ]] || {
    git -C "$src" checkout --detach "$DRIVER_COMMIT"
  }
  apply_patch "$src" "$ROOT/patches/vfs0090-ubuntu.patch"
  if [[ ! -f $ROOT/build/compiled/build.ninja ]]; then
    meson setup "$ROOT/build/compiled" "$src"
  fi
  meson compile -C "$ROOT/build/compiled"
  echo 'Build completed. Next: sudo bash install.sh install'
  ;;
install)
  need_root; check_host
  module="$ROOT/build/compiled/libfprint-tod-vfs009x.so"
  [[ -f $module ]] || { echo 'Run the build step first.' >&2; exit 1; }
  systemctl mask --now python3-validity.service
  if systemctl cat open-fprintd.service >/dev/null 2>&1; then systemctl stop open-fprintd; fi
  apt-get install fprintd fprintd-clients-
  dest=/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1
  install -d "$dest"
  if [[ -f $dest/libfprint-tod-vfs009x.so ]]; then
    cp -a "$dest/libfprint-tod-vfs009x.so" "$dest/libfprint-tod-vfs009x.so.backup-$(date +%s)"
  fi
  install -m 0644 "$module" "$dest/"
  systemctl daemon-reload
  systemctl restart fprintd
  echo 'Installed. Enroll and verify as your normal user before enabling login.'
  ;;
enable-login)
  need_root; check_host
  apt-get install libpam-fprintd
  pam-auth-update --enable fprintd
  echo 'Fingerprint authentication enabled. Lock the screen and test; keep password access available.'
  ;;
*) usage; exit 1 ;;
esac
