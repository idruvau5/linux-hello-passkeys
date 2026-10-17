#!/usr/bin/env bash
set -Eeuo pipefail

# Installs the ELAN7001 press fingerprint driver and the TPM-backed FIDO2
# authenticator. Run as the normal logged-in user; sudo is requested only for
# system packages, udev rules, and /opt installation.

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ELAN_REPO='https://github.com/goodix-fp-linux-dev/libfprint.git'
ELAN_COMMIT='07306bbc9256942595e31fb0f407b364ffa24d07'
TPM_REPO='https://github.com/duesee/tpm-fido2-thinkpad-linux.git'
TPM_COMMIT='290b7a09c440d768124e5d7973549af216a27ad8'

say() { printf '[linux-hello-passkeys] %s\n' "$*"; }
fail() { printf '[linux-hello-passkeys] ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || fail 'Run this as your normal user, not with sudo.'
command -v sudo >/dev/null || fail 'sudo is required.'
command -v git >/dev/null || fail 'git is required.'
command -v apt-get >/dev/null || fail 'This installer currently targets Debian/Ubuntu/Mint.'

if ! getent group tss >/dev/null; then
  say 'Creating the TPM access group.'
  sudo groupadd --system tss
fi

say 'Installing build and runtime dependencies.'
sudo apt-get update
sudo apt-get install -y \
  build-essential meson ninja-build pkg-config git ca-certificates \
  libglib2.0-dev libgusb-dev libusb-1.0-0-dev libpam0g-dev \
  libopencv-dev doctest-dev fprintd libpam-fprintd \
  golang-1.24-go

WORK=$(mktemp -d "${TMPDIR:-/tmp}/linux-hello-passkeys.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

say 'Building the ELAN press driver from the pinned libfprint source.'
git clone --branch sigfm --single-branch "$ELAN_REPO" "$WORK/libfprint"
git -C "$WORK/libfprint" checkout --detach "$ELAN_COMMIT"
git -C "$WORK/libfprint" apply "$REPO_ROOT/patches/elanspi-touch.patch"
meson setup "$WORK/libfprint/build" "$WORK/libfprint" \
  --prefix=/opt/libfprint-sigfm -Dbuildtype=debugoptimized -Ddrivers=all
ninja -C "$WORK/libfprint/build"
sudo ninja -C "$WORK/libfprint/build" install

say 'Installing persistent libfprint selection for fprintd.'
sudo install -d -m 755 /etc/systemd/system/fprintd.service.d
sudo install -m 644 "$REPO_ROOT/config/fprintd-elanspi.conf" \
  /etc/systemd/system/fprintd.service.d/10-elanspi-sigfm.conf
sudo systemctl daemon-reload
sudo systemctl restart fprintd

say 'Building the TPM-backed FIDO2 authenticator.'
git clone --depth 1 "$TPM_REPO" "$WORK/tpm-fido"
git -C "$WORK/tpm-fido" fetch --depth 1 origin "$TPM_COMMIT"
git -C "$WORK/tpm-fido" checkout --detach "$TPM_COMMIT"
git -C "$WORK/tpm-fido" apply "$REPO_ROOT/patches/tpm-fido-fingerprint-uv.patch"
GO_BIN=/usr/lib/go-1.24/bin/go
[[ -x "$GO_BIN" ]] || GO_BIN=$(command -v go)
mkdir -p "$HOME/bin"
(cd "$WORK/tpm-fido" && CGO_ENABLED=0 "$GO_BIN" build -ldflags='-s -w' -o "$HOME/bin/tpm-fido" tpmfido.go)
chmod 755 "$HOME/bin/tpm-fido"

say 'Installing device permissions and loading uhid.'
sudo install -m 644 "$REPO_ROOT/config/90-tpm-fido-uhid.rules" \
  /etc/udev/rules.d/90-tpm-fido-uhid.rules
sudo install -m 644 "$REPO_ROOT/config/uhid.conf" /etc/modules-load.d/uhid.conf
printf 'KERNEL=="tpmrm[0-9]*", GROUP="%s", MODE="0660", TAG+="uaccess"\n' \
  "$(id -un)" > "$WORK/91-tpm-fido-tpm.rules"
sudo install -m 644 "$WORK/91-tpm-fido-tpm.rules" /etc/udev/rules.d/91-tpm-fido-tpm.rules
sudo usermod -aG tss,plugdev "$(id -un)"
sudo udevadm control --reload-rules
sudo modprobe uhid
sudo udevadm trigger --subsystem-match=tpmrm --subsystem-match=hidraw

say 'Installing the persistent user service.'
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/tpm-fido.service" <<'UNIT'
[Unit]
Description=TPM-backed FIDO2 authenticator using fingerprint verification
After=graphical-session.target fprintd.service

[Service]
Type=simple
ExecStart=%h/bin/tpm-fido --mode=daemon
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now tpm-fido

say 'Installation complete.'
say 'Enroll a finger if needed: fprintd-enroll'
say 'Restart Chrome/Firefox once, then choose a FIDO2 security-key/passkey flow.'
say 'For Google: Passkeys and security keys -> Create passkey -> Use another device.'
say 'A logout/login may be needed for the new tss group membership on the next boot.'
