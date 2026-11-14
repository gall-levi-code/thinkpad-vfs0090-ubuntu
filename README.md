# ThinkPad VFS0090 fingerprint setup for Ubuntu 24.04

Enable fingerprint authentication for the **Validity `138a:0090`** reader on **Ubuntu 24.04 LTS, amd64**.

Validated on a ThinkPad X1 Carbon 4th Gen: enrollment, three consecutive verification matches, screen unlocking, and password fallback. Reboot persistence has not yet been confirmed. Other readers and Ubuntu versions are outside this guide's tested scope.

The individual setup steps worked on that laptop. The combined installer is newly assembled from those steps and has not been tested end-to-end on a second machine.

## Before starting

Run `lsusb -d 138a:0090`. Continue only if it lists your reader. You need an administrator account, internet access, and a working password.

**Sensor initialization clears its pairing and may erase existing Windows/Linux fingerprint enrollments.** This uses community driver code and an experimental initialization patch. Read the script before running it. Do not run this setup on an already working reader.

Download this repository using GitHub's **Code → Download ZIP**, extract it, and open a terminal in the extracted folder. Commands below run from that folder, without any machine-specific paths.

## 1. Prepare, then power off

```bash
sudo bash install.sh prepare
```

When it succeeds, **shut down completely**, wait about 20 seconds, then power on. The initialization service stays masked so it cannot race with the next step.

## 2. Initialize and install the driver

From the repository folder:

```bash
sudo bash install.sh initialize --erase-sensor
bash install.sh build
sudo bash install.sh install
```

Run commands one at a time; stop on an error and consult the [FAQ](FAQ.md). Building runs as your normal user. The script downloads checksum-verified firmware from Lenovo, initializes the reader, builds the patched driver from pinned source, and switches to Ubuntu's standard `fprintd`.

## 3. Enroll and verify

```bash
fprintd-enroll -f right-index-finger "$USER"
fprintd-verify -f right-index-finger "$USER"
```

Enrollment collects **ten samples**. Lift fully between touches, keeping the pad mostly centered with small position and angle changes. Repeat verification until you get several consistent `verify-match` results. If you already have an enrollment you intend to replace, `fprintd-delete "$USER"` deletes all your fingerprints before re-enrollment.

## 4. Enable sign-in

After verification works reliably:

```bash
sudo bash install.sh enable-login
```

Lock the screen and test fingerprint unlocking and password fallback. Then reboot and test again. Fingerprint authentication can also affect other PAM consumers, such as `sudo`; it does not replace your password or unlock encrypted disks.

## What makes this setup work?

- Patched `python-validity` initializes the sensor, then is removed from the active setup.
- Standard Ubuntu `fprintd` handles authentication through a custom VFS0090 TOD driver.
- Two state-machine calls are adapted to Ubuntu 24.04's library API.
- The driver's intended **2× image enlargement** is enabled at build time.
- Enrollment uses **ten samples instead of five**. The matching threshold remains **12**.
- The conflicting `fprintd-clients` package is removed when switching services.

No precompiled binary, fingerprint template, image, machine ID, or enrollment data is included. The driver builds locally. Patches contain diagnostic log statements for dimensions, brightness range, and feature counts; they do not write fingerprint images to disk.

## Sources and maintenance

- [python-validity](https://github.com/uunicorn/python-validity), installed via its Ubuntu PPA.
- [Initialization patch #294](https://github.com/uunicorn/python-validity/pull/294), vendored in `patches/python-validity-294.patch`.
- [VFS0090 TOD driver](https://github.com/rabbitambulance-ra/libfprint-tod-vfs0090), pinned to `6084a1545589beec0c741200b18b0902cca225ba`.
- Local driver changes are in `patches/vfs0090-ubuntu.patch`.

The custom driver is installed outside APT's package tracking. A future libfprint update may require rebuilding it. Source and packaged initialization versions may change; the installer stops if its initialization patch no longer applies.

[FAQ and recovery](FAQ.md) · [License and attribution](LICENSE)
