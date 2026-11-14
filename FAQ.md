# FAQ and recovery steps

The USB handling patch, partition-table patch, Ubuntu API adjustments, 2× image enlargement, ten-sample enrollment, and switch to standard `fprintd` are **required parts of this setup**, already included in the installer. They are not optional fixes to try after installation.

Run commands from the repository folder. Stop at the first failed step. Do not continue into a sensor reset unless the instructions specifically call for it: resetting clears pairing and may erase existing fingerprints.

## “No devices found” or “No devices available”

1. Check the hardware:

   ```bash
   lsusb -d 138a:0090
   ```

   If nothing appears, stop. This guide has no established fix for a reader that is not visible on USB.

2. Identify your installation stage. Before completing sensor initialization, use the initialization entries below. After installing the final driver, run:

   ```bash
   fprintd-list "$USER"
   systemctl status fprintd --no-pager
   journalctl -u fprintd -b --no-pager -n 80
   ```

3. If the service was removed during an interrupted package switch, follow the package-conflict entry. If the driver build/install was never completed, complete those steps in the README.
4. Run `fprintd-list "$USER"` again. Success identifies **Validity VFS0090**.
5. If the reader is still missing after completing installation, stop. No further recovery has been established here.

## “Signature verification failed … paired with another computer”

This occurred in the temporary initialization driver.

1. Complete `sudo bash install.sh prepare`. It applies the required initialization patch and masks the service.
2. Fully shut down, wait about 20 seconds, and power on.
3. If you accept clearing the sensor pairing and potentially losing prior enrollments, run:

   ```bash
   sudo bash install.sh initialize --erase-sensor
   ```

4. Look for `Sensor initialization completed.`
5. Continue with the build and install steps in the README. If the pairing error remains, stop; no additional fix has been established.

## Factory reset reports `USBTimeoutError: [Errno 110]`

1. Ensure the required patch is installed by completing:

   ```bash
   sudo bash install.sh prepare
   ```

2. Block the initialization service from being started by udev:

   ```bash
   sudo systemctl mask --now python3-validity.service
   ```

3. Fully shut down, wait about 20 seconds, and power on.
4. Retry initialization only if you accept clearing existing sensor pairing/enrollments:

   ```bash
   sudo bash install.sh initialize --erase-sensor
   ```

5. If initialization completes, continue with the README. If it still times out, stop. Do not keep resetting the sensor.

Disabling the service alone was insufficient during setup; masking prevented the startup race.

## The standalone reset script prints nothing

1. Confirm the command returned without a traceback. That was the successful standalone reset result during setup.
2. Do not repeatedly reset just to obtain output.
3. Follow the README's initialization procedure; the combined installer should print `Sensor initialization completed.`
4. Complete driver installation, then check:

   ```bash
   fprintd-list "$USER"
   ```

5. Expect **Validity VFS0090**. If initialization failed, use the entry matching its actual error rather than assuming silence proves the entire setup works.

## Initialization fails with `Failed: 04af`

The required partition-table patch handles the identified older ROM. It must be applied before reinitializing.

1. Complete:

   ```bash
   sudo bash install.sh prepare
   ```

   Stop if the patch does not apply; do not force it.

2. Fully shut down, wait about 20 seconds, and power on.
3. Accepting the loss of existing sensor pairing/enrollments, run:

   ```bash
   sudo bash install.sh initialize --erase-sensor
   ```

4. Confirm `Sensor initialization completed.`, then continue with the README.
5. If `04af` persists with the patch applied, stop. The patch is not a verified fix for every ROM.

Reference: [initialization patch #294](https://github.com/uunicorn/python-validity/pull/294).

## Firmware file `6_07f_Lenovo.xpfwext` is missing during initialization

1. While the temporary initialization tools are still installed, run:

   ```bash
   sudo validity-sensors-firmware
   ```

2. Confirm the download, checksum verification, and extraction finish without error. Do not bypass a checksum failure.
3. Retry the interrupted initialization step. The combined `initialize` command already downloads firmware before resetting.
4. Stop if downloading or initialization still fails.

The packaged tool uses temporary storage under `/var/run/python-validity`, cleared on reboot. The final setup removes the Python driver and does not depend on that temporary file. This command is not a BIOS update.

## Enrollment immediately fails with `0401`

1. Check which driver is active:

   ```bash
   fprintd-list "$USER"
   ```

2. If it says **DBus driver**, the final service switch has not been completed. After successful sensor initialization, run:

   ```bash
   bash install.sh build
   sudo bash install.sh install
   ```

3. Confirm the device now identifies as **Validity VFS0090**.
4. Enroll:

   ```bash
   fprintd-enroll -f right-index-finger "$USER"
   ```

5. Expect ten samples followed by `enroll-completed`. If enrollment fails with the final driver, stop; do not apply further sensor resets.

## APT tries to overwrite `/usr/bin/fprintd-delete`

1. Remove the conflicting community client while installing Ubuntu's standard service:

   ```bash
   sudo apt-get install fprintd fprintd-clients-
   ```

2. Once that succeeds, finish installing the built driver:

   ```bash
   sudo bash install.sh install
   fprintd-list "$USER"
   ```

3. Expect **Validity VFS0090**. If APT reports a different error, stop.

The trailing minus requests removal of `fprintd-clients`. Do not use `dpkg --force-overwrite`.

## The compiler reports “too many arguments” to `fpi_ssm_next_state_delayed`

1. Confirm this is Ubuntu 24.04 amd64:

   ```bash
   cat /etc/os-release
   dpkg --print-architecture
   ```

2. Build using the repository's patched build step, rather than compiling unmodified upstream source:

   ```bash
   bash install.sh build
   ```

3. The included patch removes the extra `NULL` argument from both affected calls.
4. If the build succeeds, run `sudo bash install.sh install`.
5. If the patch fails to apply or compilation still fails, stop. Do not adapt these API changes to another libfprint version without investigation.

## Enrollment completes but verification is unreliable

The required build enables 2× enlargement and ten enrollment samples. The matching threshold stays at 12.

1. Ensure the complete patched build is installed:

   ```bash
   bash install.sh build
   sudo bash install.sh install
   ```

2. Clean and dry the sensor and your finger.
3. Replace the old enrollment. **The delete command removes all fingerprints enrolled for your user:**

   ```bash
   fprintd-delete "$USER"
   fprintd-enroll -f right-index-finger "$USER"
   ```

4. Complete all ten samples. Lift fully between touches. Keep the finger mostly centered, with small position and angle changes representative of normal unlocking.
5. Run verification three times, touching the enrolled finger each time:

   ```bash
   fprintd-verify -f right-index-finger "$USER"
   ```

6. Look for consistent `verify-match` results. Our confirmed result was three consecutive matches and successful screen unlocking.
7. If matching remains unreliable, stop before enabling fingerprint authentication. No additional confirmed fix is documented.

## Should I lower the matching threshold?

1. Keep the supplied threshold of 12.
2. Follow the verification entry above to confirm the required image processing and ten-sample enrollment are in place.
3. If recognition remains unreliable, stop; this guide does not establish a safe alternative threshold.

Our functional checks are not a biometric security evaluation.

## How do I collect diagnostic logs?

1. Enable temporary logging:

   ```bash
   sudo mkdir -p /run/systemd/system/fprintd.service.d
   printf '[Service]\nEnvironment=G_MESSAGES_DEBUG=all\n' | sudo tee /run/systemd/system/fprintd.service.d/vfs0090-debug.conf
   sudo systemctl daemon-reload
   sudo systemctl restart fprintd
   ```

2. Reproduce one verification failure and read the logs:

   ```bash
   fprintd-verify -f right-index-finger "$USER"
   journalctl -u fprintd -b --no-pager -n 300
   ```

3. Review logs locally. Remove usernames, machine names, and personal paths before sharing. Never share fingerprint templates or raw fingerprint images.
4. Remove temporary logging:

   ```bash
   sudo rm -f /run/systemd/system/fprintd.service.d/vfs0090-debug.conf
   sudo systemctl daemon-reload
   sudo systemctl restart fprintd
   ```

Collecting logs does not itself resolve a failure.

## A “System program problem detected” prompt appears

1. Note which command immediately preceded the prompt.
2. For the final driver, inspect:

   ```bash
   journalctl -u fprintd -b --no-pager -n 80
   ```

   During temporary initialization, use:

   ```bash
   journalctl -u python3-validity -b --no-pager -n 80
   ```

3. Match the actual error to an entry above and follow that entry's steps. For a package overwrite error, follow the APT entry.
4. Retry the originally interrupted installation step after the specific error is resolved.
5. If no documented error matches, stop. The popup alone does not establish a cause, and an old crash report may remain after the underlying problem is resolved.

## Does it work after reboot or suspend?

**Yes, the original user confirmed operation after both reboot and suspend on the tested laptop.** This does not guarantee every reader/ROM combination.

1. Establish reliable command-line verification and screen unlocking.
2. Reboot, then test fingerprint authentication.
3. Suspend and resume, then test it again.
4. If either test fails, use your password. Stop before resetting or reinstalling: we have not established a recovery procedure for a persistence failure.

## How do I return to password-only authentication?

1. Keep your current session open and disable fingerprint authentication:

   ```bash
   sudo pam-auth-update --disable fprintd
   ```

2. Confirm password authentication works before closing that session.
3. If you also want to remove this custom driver, run:

   ```bash
   sudo systemctl stop fprintd
   sudo rm -f /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-tod-vfs009x.so
   sudo systemctl start fprintd
   ```

4. Continue using your password.

This does not undo the sensor reset or restore erased fingerprints. Build dependencies and the PPA remain installed. Do not unmask the old initialization service unless deliberately returning to that troubleshooting stage.
