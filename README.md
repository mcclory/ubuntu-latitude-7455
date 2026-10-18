# Ubuntu 26.10 ARM64 on a Dell Latitude 7455 (Snapdragon X Elite X1E-80-100)

Field notes, how-tos and small scripts from getting Ubuntu 26.10 ARM64 running as a daily development machine on one used Dell Latitude 7455 (X1E-80-100, 32 GB, QHD+ touch panel).

**One unit.** Everything here was observed on a single laptop. Panel and touch-controller variants exist; check your own hardware before applying anything that changes boot or device-tree configuration.

**No firmware here.** The Qualcomm firmware this laptop needs comes from the Windows driver store on your own machine. This repository does not contain, link to or redistribute any firmware binaries. Back up `C:\Windows\System32\DriverStore\FileRepository` before you wipe Windows.

Write-ups and bug reports:

* [reports/discourse-article.md](reports/discourse-article.md): the write-up for the Ubuntu Concept team (brightness, touchscreen, camera privacy LED, firmware extraction), with a full device matrix.
* Launchpad:
  * [LP #2171350](https://bugs.launchpad.net/ubuntu/+source/qcom-firmware-extract/+bug/2171350): `qcom-firmware-extract -d` fails when Windows is gone
  * [LP #2171351](https://bugs.launchpad.net/ubuntu/+source/qcom-firmware-extract/+bug/2171351): `qcvss8380.mbn` not extracted
  * [LP #2171354](https://bugs.launchpad.net/ubuntu-concept/+bug/2171354) (also [LP #2171352](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2171352)): touchscreen at `0x34` / descriptor register 0
  * [LP #2171357](https://bugs.launchpad.net/ubuntu-concept/+bug/2171357): camera privacy LED not linked to the sensor
  * Brightness: same symptom as [LP #2159387](https://bugs.launchpad.net/ubuntu-concept/+bug/2159387)

## Contents

| Path | What it is |
|---|---|
| [docs/firmware.md](docs/firmware.md) | Extracting firmware from a DriverStore backup with `qcom-firmware-extract -d`, the v20 guard bug, the missing `qcvss8380.mbn` |
| [docs/touchscreen.md](docs/touchscreen.md) | Touchscreen at I2C `0x34` instead of `0x09`: how it was identified, the three-line DT correction, the GRUB entry, `stubble.dtb_override=false`, rollback |
| [docs/dev-environment.md](docs/dev-environment.md) | VS Code extensions need `libssl3t64`, Playwright with the system Chrome, `sg`/`newgrp` absent on 26.10, Docker group, COSMIC repo signing |
| [docs/known-issues.md](docs/known-issues.md) | Open issues: backlight, post-resume speaker, PCIe L2 timeout, battery state |
| [patches/](patches/) | One-line fix for `qcom-firmware-extract` 20 when given `-d` |
| [reports/](reports/) | The Concept-team write-up, the Launchpad bug texts, and redacted evidence attachments |
| [scripts/](scripts/) | Read-only collectors, the approval-gated bus probe and descriptor read used for the touchscreen, the DT-fix script, and `cap`, a capture/timeline helper |

## Environment

* Ubuntu 26.10 ARM64: the Snapdragon Concept image on the first build; the generic daily image plus the Concept kernel PPA, with LUKS full-disk encryption, on the second
* Kernel `7.3.0-21-qcom-x1e` from `ppa:ubuntu-concept/x1e`
* BIOS 2.16.0
* COSMIC desktop, Chrome, VS Code

## Safety

Scripts that only read state say so in their header. `probe-touchscreen-addresses.py` and `read-touchscreen-candidate.py` perform I2C transactions on one bus and refuse to run without guards; `touchscreen-dt-fix.sh` writes to `/boot`. Read them first. Nothing here touches GPIOs, amplifier gain or firmware partitions.

## License

MIT, see [LICENSE](LICENSE). Firmware is not included and not covered: it belongs to Qualcomm and Dell, and you extract it from your own machine.
