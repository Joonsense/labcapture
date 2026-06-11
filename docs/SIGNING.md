# Local signing certificate — keep TCC permissions across rebuilds

Ad-hoc signing (`codesign -s -`) produces a new CDHash on every build, and macOS TCC
permissions (Screen Recording) are bound to that hash — so **every rebuild silently
invalidates the permission**. System Settings still shows the toggle as ON, but the
record points at the old signature and capture fails with ffmpeg
`Configuration of video device failed`. The fix at that point is:

```bash
tccutil reset ScreenCapture com.deblockx.labcapture
# relaunch the app, re-grant the permission
```

To make permissions survive rebuilds, create a local self-signed code-signing
certificate named **"LabCapture Dev"**. `build.sh` auto-detects it in your keychain and
uses it; the designated requirement becomes `identifier + certificate leaf`, which is
stable across builds. Without the certificate, `build.sh` falls back to ad-hoc signing.

## One-time setup

```bash
PASS=$(openssl rand -hex 16)
mkdir -p ~/.config/labcapture
printf '%s' "$PASS" > ~/.config/labcapture/sign_keychain_pass
chmod 600 ~/.config/labcapture/sign_keychain_pass

cd /tmp
openssl req -x509 -newkey rsa:2048 -keyout lc_key.pem -out lc_cert.pem -days 3650 -nodes \
  -subj "/CN=LabCapture Dev" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:FALSE"
openssl pkcs12 -export -legacy -out lc.p12 -inkey lc_key.pem -in lc_cert.pem \
  -password pass:"$PASS" -name "LabCapture Dev"

security create-keychain -p "$PASS" labcapture-sign.keychain
security set-keychain-settings labcapture-sign.keychain   # disable auto-lock
security unlock-keychain -p "$PASS" labcapture-sign.keychain
security import lc.p12 -k labcapture-sign.keychain -P "$PASS" -T /usr/bin/codesign
security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -k "$PASS" labcapture-sign.keychain
security list-keychains -d user -s login.keychain "$HOME/Library/Keychains/labcapture-sign.keychain-db"

# Trust it for code signing (one GUI password prompt)
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" lc_cert.pem

rm -f lc_key.pem lc.p12 lc_cert.pem
```

Then rebuild:

```bash
./build.sh   # prints: 서명: LabCapture Dev (TCC 권한 유지됨)
```

## Notes

- `-legacy` is required on the `openssl pkcs12 -export` step: OpenSSL 3's default
  PKCS#12 format cannot be read by macOS Security ("MAC verification failed").
- Creating a *new* certificate changes the signature one final time — you must
  re-grant Screen Recording once after switching from ad-hoc to the certificate
  (and once more if you ever regenerate the certificate).
- The certificate is valid for 10 years and lives in its own keychain
  (`labcapture-sign`), whose password is stored at
  `~/.config/labcapture/sign_keychain_pass` (chmod 600). It can only sign code
  locally; it grants no trust to anyone else's machine.
