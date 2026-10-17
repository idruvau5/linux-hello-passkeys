# Linux ELAN fingerprint and TPM-FIDO passkeys

> Legacy combined package. The maintained components are now split into separate repositories: [ELAN7001 fingerprint](https://github.com/idruvau5/asus-elan7001-fingerprint-linux), [TPM-FIDO passkeys](https://github.com/idruvau5/linux-tpm-fido-passkeys), [VivoBook audio](https://github.com/idruvau5/asus-vivobook-audio-fix), and [VivoBook display color](https://github.com/idruvau5/asus-vivobook-display-color).

This package reproduces the working configuration for ASUS VivoBook models exposing an ELAN7001/eFSA96SA fingerprint sensor. It builds the community ELAN SPI `sigfm` libfprint branch with a Windows-style press capture path, then installs a TPM-backed FIDO2 HID authenticator. The fingerprint sensor authorizes passkeys and WebAuthn operations; private credential keys remain protected by the TPM.

The FIDO2 authenticator is global at the standard HID/WebAuthn layer. Chrome, Firefox, and password managers that support FIDO2 can use it. It is not Microsoft’s Windows Hello binary. Linux login remains provided by fprintd.
The installer disables the bridge’s persistent desktop notification by default; the browser or password manager supplies the prompt. Set `TPM_FIDO_NOTIFY=1` only if you want a short four-second desktop reminder.

## One-command install

Run this as the normal logged-in user:

```bash
curl -fsSL https://raw.githubusercontent.com/idruvau5/linux-hello-passkeys/v0.1.0/install.sh -o /tmp/install-linux-hello-passkeys.sh
bash /tmp/install-linux-hello-passkeys.sh
```

The script is pinned to the source commits recorded in `install.sh`, applies the two reviewed patches, installs the fprintd library under `/opt/libfprint-sigfm`, enables `tpm-fido.service`, and leaves enrollment to you.

## Google passkeys

Google’s computer passkey flow may show a Google Password Manager PIN. That PIN is separate from the fingerprint authenticator. Use **Passkeys and security keys → Create passkey → Use another device** to select the FIDO2 security-key path, then touch the enrolled finger.

## Verify

```bash
systemctl --user status tpm-fido
python3 - <<'PY'
from fido2.hid import CtapHidDevice
from fido2.ctap2 import Ctap2
for device in CtapHidDevice.list_devices():
    info = Ctap2(device).get_info()
    print(device.product_name, info.options, info.pin_uv_protocols)
PY
```

Expected: device `tpm-fido`, options containing `rk`, `up`, and `uv` set to true, and no advertised PIN protocol. See `docs/current-configuration.md` for the full machine report.

## Source and licensing

The installer and configuration are MIT-licensed. It builds the pinned upstream [libfprint](https://github.com/goodix-fp-linux-dev/libfprint) and [tpm-fido](https://github.com/duesee/tpm-fido2-thinkpad-linux) sources under their respective licenses. The virtual authenticator is experimental; a hardware FIDO2 security key remains the strongest independent fallback.
