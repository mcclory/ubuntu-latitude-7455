# Firmware from your own Windows driver store

The GPU, audio DSPs and video (IRIS) blocks need model-specific Qualcomm firmware that Ubuntu does not ship. The copy you're entitled to is in the Windows install on your laptop. Get it before you wipe Windows.

## 1. Back up the driver store (in Windows)

1. Update the BIOS through Windows Update first (this unit: 2.16.0).
2. Copy `C:\Windows\System32\DriverStore\FileRepository` to separate media, for example with `robocopy`, and check that source and destination file counts match. On this unit: 2,213 files, about 1.9 GiB.

Keep this copy. Do not download these files from third-party sites and do not redistribute what you extract.

## 2. Extract with `qcom-firmware-extract -d`

```bash
sudo apt install -y qcom-firmware-extract device-tree-compiler mesa-utils
DS=/path/to/backup/FileRepository          # mount the backup read-only
sudo qcom-firmware-extract -d "$DS"
```

### Version 20 fails with `Failed to find windows partition`

Version 20 accepts `-d <dir>` but a later guard still exits when no Windows partition was discovered, even though a search path was given. Reproduced on two clean installs (2026-10). The fix is one line; see [../patches/qcom-firmware-extract-v20-search-path-guard.patch](../patches/qcom-firmware-extract-v20-search-path-guard.patch).

Patch a copy, not the packaged file:

```bash
cp "$(command -v qcom-firmware-extract)" ~/qcom-firmware-extract-fixed
# -F matters: on 26.10 `grep` may be ugrep, where a mid-pattern $ is an anchor
L=$(grep -nF 'if [ -z "$part" ]; then' ~/qcom-firmware-extract-fixed | tail -1 | cut -d: -f1)   # line 108 in v20
sed -i "${L}s/if \[ -z \"\$part\" \]; then/if [ -z \"\$part\" ] \&\& [ -z \"\$search_path\" ]; then/" ~/qcom-firmware-extract-fixed
diff "$(command -v qcom-firmware-extract)" ~/qcom-firmware-extract-fixed   # exactly one changed line
sudo bash ~/qcom-firmware-extract-fixed -d "$DS"
```

If the packaged tool works unpatched, the bug has been fixed; note the version.

The extractor builds and installs a local package (`qcom-x1e-firmware-extracted-x1e80100-dell-latitude7455`) with 11 files under `/usr/lib/firmware/updates/qcom/x1e80100/dell/latitude-7455/`.

## 3. Add `qcvss8380.mbn` by hand

The IRIS video driver asks for `qcvss8380.mbn`, which the extractor does not include. It is in the driver store backup:

```bash
FW=/usr/lib/firmware/updates/qcom/x1e80100/dell/latitude-7455
SRC=$(find "$DS" -path '*qcdx8380.inf_arm64_*' -name qcvss8380.mbn | head -1)
sudo install -Dm644 "$SRC" "$FW/qcvss8380.mbn"
sha256sum "$SRC" "$FW/qcvss8380.mbn"     # hashes must match
ls "$FW" | wc -l                         # 12
```

## 4. Rebuild the initramfs and reboot

This image uses Dracut, not initramfs-tools:

```bash
sudo dracut --force --kver "$(uname -r)"
```

After rebooting:

```bash
glxinfo -B | grep -E 'direct rendering|renderer|OpenGL version'   # Adreno X1-85, Mesa freedreno
wpctl status | sed -n '/Audio/,/Video/p'                          # real sinks, not Dummy Output
journalctl -k -b | grep -iE 'qcvss|iris'                          # no missing-firmware error
```

The IRIS decoder and encoder then enumerate (`qcom-iris-decoder`, `qcom-iris-encoder`). Enumeration alone does not prove hardware decode in a browser.

Install a newer kernel (below) afterwards; firmware lives under `updates/` and is not kernel-specific.

## Kernel

The generic image boots `7.3.0-9-generic`. The Concept PPA carries the Snapdragon kernel:

```bash
sudo add-apt-repository -y ppa:ubuntu-concept/x1e
sudo apt install linux-qcom-x1e      # 7.3.0-21-qcom-x1e here; the generic kernel stays as a fallback
```

On `7.3.0-15` deep suspend left Wi-Fi dead (`ath12k ... failed to resume core: -110`); on `7.3.0-21` power-button wake and Wi-Fi resume worked in the few short cycles tested so far. That is not a reliability claim.
