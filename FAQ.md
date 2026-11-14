# FAQ

## Why not use Ubuntu's default driver alone?

On the tested setup, Ubuntu's standard libfprint installation reported no devices for `138a:0090`. A custom TOD driver supplied reader support while preserving standard `fprintd` for authentication.

## “No devices found” or “No devices available”

This is a symptom, not a diagnosis. Check:

```bash
lsusb -d 138a:0090
systemctl status fprintd --no-pager
journalctl -u fprintd -b --no-pager -n 80
```

During initialization, inspect `python3-validity` instead. It should remain masked when using the final driver. Do not repeatedly reset the reader as a general troubleshooting step.

## “Signature verification failed … paired with another computer”

The initialization driver cannot validate the sensor's existing pairing. A sensor reset resolved this during our setup. Resetting can erase prior enrollments. Use the documented initialization step; do not bypass signature verification in the code.

## Factory reset reports `USBTimeoutError: [Errno 110]`

The driver may already have touched the sensor, or USB configuration handling may be causing lost responses. The initialization patch addresses reselecting an active USB configuration. Mask the service, fully shut down, wait 20 seconds, and retry initialization after powering on:

```bash
sudo systemctl mask --now python3-validity.service
```

Disabling the service alone was insufficient: a udev rule could still start it. Masking prevents that. If a timeout persists after the patch and a fresh power-on, stop and collect logs rather than repeatedly resetting.

## The reset script prints nothing

That was the successful result in our setup. No output alone does not prove the whole installation works; complete initialization and verify detection afterward.

## Initialization fails with `Failed: 04af`

Our reader's ROM could not use the signed partition table sent by the packaged initialization driver. [Patch #294](https://github.com/uunicorn/python-validity/pull/294) handles the identified ROM version and prevents the resulting corrupted table. Apply the patch before resetting/reinitializing. It is experimental and does not claim support for every ROM.

## Firmware file `6_07f_Lenovo.xpfwext` is missing

The packaged tool stores it under `/var/run/python-validity`, which is temporary. During initialization, restore the extracted file with:

```bash
sudo validity-sensors-firmware
```

This downloads Lenovo's driver archive, checks the expected SHA-512, and extracts firmware. It is not a BIOS update. The installer runs it before initialization. The final setup removes `python3-validity` and no longer relies on that temporary Python-driver file.

## Enrollment immediately fails with `0401`

We saw this with `python-validity`, even after successful pairing. The final setup uses the VFS0090 TOD driver and standard `fprintd` instead. `fprintd-list "$USER"` should identify **Validity VFS0090**, rather than **DBus driver**.

## APT tries to overwrite `/usr/bin/fprintd-delete`

The community `fprintd-clients` package owns files also supplied by standard `fprintd`. The installer switches with:

```bash
sudo apt-get install fprintd fprintd-clients-
```

The trailing minus explicitly removes the conflicting package. Avoid using `dpkg --force-overwrite`.

## The compiler says “too many arguments” to `fpi_ssm_next_state_delayed`

Ubuntu 24.04's installed headers use a two-argument API. The local driver patch removes the extra `NULL` from both calls. Do not reuse these changes blindly against another libfprint version.

## Enrollment completes but every verification fails

Our initial build left image enlargement disabled, despite the source containing an enlargement path. The build patch defines `HAVE_PIXMAN=1`, enabling 2× enlargement from 144×144 to 288×288 before feature extraction.

After changing image processing, replace the old enrollment. Five samples still proved unreliable for us; ten samples with modest placement variation produced three consecutive matches and successful unlocking. Clean and dry the sensor and finger, and lift fully between touches.

## Why not lower the matching threshold?

We left it at 12. Instead, we corrected image processing and increased enrollment coverage. One successful match is insufficient evidence of reliable recognition; test several times before enabling authentication. Our limited tests are not a biometric security evaluation.

## How do I enable temporary diagnostic logging?

```bash
sudo mkdir -p /run/systemd/system/fprintd.service.d
printf '[Service]\nEnvironment=G_MESSAGES_DEBUG=all\n' | sudo tee /run/systemd/system/fprintd.service.d/vfs0090-debug.conf
sudo systemctl daemon-reload
sudo systemctl restart fprintd
fprintd-verify -f right-index-finger "$USER"
journalctl -u fprintd -b --no-pager -n 300
```

Review logs before posting them: they can contain usernames and local paths. Do not publish fingerprint templates or raw images. Remove the temporary setting when finished:

```bash
sudo rm -f /run/systemd/system/fprintd.service.d/vfs0090-debug.conf
sudo systemctl daemon-reload
sudo systemctl restart fprintd
```

## A “System program problem detected” prompt appears

We saw crash reports from failed initialization and an interrupted package installation. Inspect the service logs and fix the underlying error. The dialog alone does not identify the cause. Old reports may remain after the cause has been fixed.

## Does it survive reboot or suspend?

Reboot and suspend/resume remain validation steps for this guide. Enrollment, matching, unlocking, and password fallback were confirmed in one running session. Please include reader ID, Ubuntu/libfprint versions, and sanitized logs when reporting persistence problems.

## How do I return to password-only authentication?

```bash
sudo pam-auth-update --disable fprintd
```

Keep the current session open and confirm password authentication works. To remove this custom driver as well:

```bash
sudo systemctl stop fprintd
sudo rm -f /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-tod-vfs009x.so
sudo systemctl start fprintd
```

These steps do not reverse the sensor reset or restore fingerprints erased earlier. The initialization package's original files are backed up under `/var/backups/vfs0090.*`; the package itself is removed during the service switch. Build dependencies and the PPA remain installed. Do not unmask the old initialization service unless deliberately troubleshooting it.
