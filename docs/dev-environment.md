# Development environment notes (Ubuntu 26.10 ARM64)

## VS Code: extensions fail signature verification

VS Code 1.141.0 ARM64 (official `.deb`) installs, but every extension install fails signature verification. Running the bundled `vsce-sign` verifier directly gives the real error:

```text
No usable version of libssl was found
```

Ubuntu 26.10 ships OpenSSL 4; the verifier needs OpenSSL 3. Install the packaged compatibility library:

```bash
sudo apt install libssl3t64
```

Signature checking stays on. Do not disable verification to get past this.

To install the `.deb` without adding Microsoft's apt repository, preseed the debconf answer and verify the download against the update API's hash:

```bash
curl -fsSL https://update.code.visualstudio.com/api/update/linux-deb-arm64/stable/latest \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["url"]);print(d["sha256hash"])' > code.meta
curl -fsSLo code-arm64.deb "$(sed -n 1p code.meta)"
echo "$(sed -n 2p code.meta)  code-arm64.deb" | sha256sum -c -
echo "code code/add-microsoft-repo boolean false" | sudo debconf-set-selections
sudo apt install ./code-arm64.deb libssl3t64
```

Without the repository, updates are manual.

## Chrome

Google publishes an ARM64 `.deb` (`google-chrome-stable_current_arm64.deb`); the package adds Google's signed apt source. For the camera in WebRTC under PipeWire, enable `chrome://flags/#enable-webrtc-pipewire-camera`. Camera, microphone and screen share in a Google Meet call worked under COSMIC.

## Playwright: use the system Chrome

Playwright's bundled browser installer rejects Ubuntu 26.10 ARM64. Forcing the `ubuntu24.04-arm64` build downloads a Chromium, but Ubuntu's AppArmor policy blocks its sandbox. Pointing tests at the installed Chrome works with the sandbox intact, e.g. in `playwright.config.ts`:

```ts
use: { channel: 'chrome' }
```

Do not disable the sandbox or AppArmor to make the bundled browser run.

## `sg` and `newgrp` are gone

On 26.10 the `login` package is built from util-linux, and `sg` is no longer shipped by any package. `newgrp` is available in `util-linux-extra` (setuid root). After `sudo usermod -aG docker "$USER"`, the group applies at next login. To use it before then without either tool:

```bash
sudo -u "$USER" -g docker docker run --rm hello-world
```

## Docker

`docker.io` 29.7.2 and `docker-compose-v2` 2.40.3 from the Ubuntu archive work on ARM64, including ARM64 Postgres/pgvector containers for integration tests. Ports published by Docker bypass `ufw` rules.

## Other tools

kubectl, Helm, Argo CD, Velero, k9s, krew, the cilium CLI, yq and Vault all publish `linux-arm64` binaries with checksum files; verify each download. `uv` and `nvm` installers work; Node 24 LTS ARM64 builds are available.

## COSMIC from the Pop!_OS repository

COSMIC installs from `apt.pop-os.org/release` (noble) with a low pin. On 26.10, apt's Sequoia verifier rejects the repository key because its self-signatures use SHA-1 (`SHA1 is not considered secure since 2026-02-01`), so apt reports the repository as unsigned. One workaround is extending the SHA-1 cutoff in `/etc/crypto-policies/back-ends/apt-sequoia.config`. That setting applies to every repository, not just Pop!_OS; decide whether you accept that, and set a date to revisit it. `apt update` warns ahead of the cutoff (`Policy will reject signature within a year`).

Under COSMIC, `snapd-desktop-integration` crash-loops (AppArmor denies its portal registration); removing that snap or disabling its user unit stops it.
