# Linux Windows-Hello-style fingerprint passkeys

This laptop is an ASUS VivoBook X530FN/S530FN with an ELAN7001 fingerprint sensor. Linux login uses `fprintd`; browser passkeys use a separate FIDO2 authenticator. The configured bridge is a TPM-backed virtual FIDO2 security key: the private credential key is kept in `/dev/tpmrm0` and an enrolled fingerprint authorizes each sign-in or registration.

## Current configuration

- Source: https://github.com/duesee/tpm-fido2-thinkpad-linux
- Source commit: 290b7a09c440d768124e5d7973549af216a27ad8
- Local source: `$HOME/.cache/rea-review/tpm-fido`
- Installed binary: `$HOME/bin/tpm-fido`
- User service: `tpm-fido.service` (enabled, starts at graphical login)
- Credential metadata: `~/.local/share/tpm-fido/credentials.json`
- Virtual HID device: `/dev/hidraw*`, FIDO2 VID `1209`, PID `F1D0`
- TPM access rule: `/etc/udev/rules.d/91-tpm-fido-tpm.rules`
- uhid rule: `/etc/udev/rules.d/90-tpm-fido-uhid.rules`
- Enrolled fingerprint daemon: `fprintd` (`press` mode)
- CTAP PIN capability: intentionally not advertised; fingerprint UV is used instead
- Desktop notification: disabled by default to prevent stale Cinnamon popups; browser prompt is authoritative
- ELAN capture behavior: one press frame, then acquisition stops immediately; this prevents the Linux wait-up polling loop from triggering the sensor thermal guard

## Verify after login/reboot

```bash
systemctl --user status tpm-fido
ls -l /dev/hidraw*
python3 - <<'PY'
from fido2.hid import CtapHidDevice
from fido2.ctap2 import Ctap2
for device in CtapHidDevice.list_devices():
    print(device.product_name, device.serial_number)
    print(Ctap2(device).get_info().options)
PY
```

Expected output includes a device named `tpm-fido` and options containing `rk: True`, `up: True`, `uv: True`.

## Use in Chrome, Firefox, or password managers

1. Leave `tpm-fido.service` running.
2. Restart the browser once after boot so it enumerates the virtual security key.
3. On a site, choose **Create passkey** or **Use a security key**. The authenticator should request a fingerprint, not a FIDO PIN; touch the enrolled right-middle finger on the sensor.
4. Password managers that support WebAuthn/FIDO2 can use the same authenticator as a security key.

For Google specifically, use **Create a passkey → Use another device** when the normal computer passkey screen opens. That selects the FIDO2 security-key path, which is the path exposed by this Linux authenticator. Google documents this flow for FIDO2 keys at https://support.google.com/accounts/answer/13548313.

This is a Linux FIDO2 authenticator, not Microsoft's Windows Hello binary. It supplies the same user experience (TPM-protected key plus fingerprint approval) through the standard WebAuthn/FIDO2 interface. A USB FIDO2 key or a phone remains the fallback for sites that reject virtual/security-key authenticators.

## Rebuild or restore

```bash
cd $HOME/.cache/rea-review/tpm-fido
PATH=/usr/lib/go-1.24/bin:$PATH CGO_ENABLED=0 go build -ldflags='-s -w' -o $HOME/bin/tpm-fido tpmfido.go
systemctl --user restart tpm-fido
```

Do not run `fprintd-enroll`, `fprintd-verify`, Fingwit enrollment, and a browser passkey prompt at the same time: all of them claim the single sensor. The Linux driver now stops after the single press image, matching the Windows flow and avoiding continuous high-power polling.
