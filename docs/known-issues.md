# Known issues

Observed on one Latitude 7455 (X1E-80-100), Ubuntu 26.10 ARM64, kernel `7.3.0-21-qcom-x1e`, October 2026. Diagnoses are labelled where they are hypotheses.

## Display brightness does not work

`/sys/class/backlight/dp_aux_backlight` exists with `max_brightness=0`; the brightness keys emit the correct key codes but nothing changes. Every boot logs:

```text
panel-simple-dp-aux aux-aea0000.displayport-controller: Unknown panel LGD 0x0754, using conservative timings
```

preceded by a warning in `generic_edp_panel_probe` (`drivers/gpu/drm/panel/panel-edp.c`). The message was recorded on every boot checked on `7.3.0-15` and `7.3.0-21`, with stock and corrected device trees; `max_brightness=0` also on `7.3.0-9-generic` after a clean reinstall.

Hypothesis (unverified): this panel (LG Display `0x0754`) is missing from `panel-edp`'s table, and the AUX backlight probe then reports no usable range. Like the touchscreen, it may be a panel-assembly variant.

## Speaker can fail after resume

After some deep-suspend cycles, opening speaker playback fails:

```text
wsa884x-codec sdw:1:0:0217:0204:00:0: ASoC error (-61): at snd_soc_pcm_component_pm_runtime_get()
qcom-soundwire 6b10000.soundwire: swrm_wait_for_wr_fifo_avail err write overflow
```

PipeWire then drops the speaker sink and the default sink is unset, so volume keys report no active sink. Seen twice; other resumes were clean, and once the speaker came back muted and unmuting fixed it. A reboot restores it. Not investigated by reloading modules or changing amplifier settings (speaker protection).

## PCIe L2 entry timeout on suspend

```text
qcom-pcie 1c08000.pcie: Timeout waiting for L2 entry! LTSSM: 0x11
```

Recurs on suspend. Resume and Wi-Fi have worked when it appears; impact unknown.

## Battery reports charging with nothing connected

With every power source reporting `online: no`, `upower` shows the battery `state: charging` at `energy-rate: 0 W`. Full capacity reads 46.43 Wh against 54 Wh design (86%) at 5 charge cycles, identical across two installs. Not diagnosed.

## Audio DSP command timeout at boot

One `qcom-apm gprsvc:service:2:1: CMD timeout for [1001021] opcode` per boot in some boots. No user-visible effect identified.

## Touchscreen needs a corrected device tree

See [touchscreen.md](touchscreen.md). Kernel-pinned; redo per kernel.

## Camera image quality

The OV02E10 sensor streams through libcamera 0.7.0 (about 30 fps), but libcamera reports missing tuning and sensor-helper support for it; images are grainy and desaturated. Black frames were the physical privacy shutter, not a driver problem.

## Firmware extractor

See [firmware.md](firmware.md): `qcom-firmware-extract` 20 ignores `-d` when no Windows partition exists, and omits `qcvss8380.mbn`.
