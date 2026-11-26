# installing the tower from the prepared usb

the usb contains the official arch live environment, `start-desktop`, and a git bundle of the workstation configuration. the bundle supplies the checkout. installing arch packages requires ethernet and an internet connection.

1. disconnect the backup drives. on the tower, tap `F12` and select the uefi entry for the usb. boot the arch installation medium. if the firmware refuses the official image, switch secure boot off.
2. at the live root prompt, run the launcher below. it loads the bundled revision and displays the attached disks. match the internal nvme's model, serial and capacity against the drive you intend to erase. enter its device path. review the displayed disk and partition layout before typing the requested confirmation.

   ```sh
   bash /run/archiso/bootmnt/start-desktop
   ```

3. the installer creates a 1 gib efi partition and an unencrypted ext4 root, installs stock arch and the boot loader, and copies its own repo revision to `/home/nnandal/Projects/dev-server`. if the usb carries `operator.pub`, the installer shows the key fingerprint and authorizes that public key for ssh on the new account. when prompted, enter the password for `nnandal` twice. keep it local.
4. when the installer reports success, run `poweroff`, remove the usb, and start the tower. log in as `nnandal` at the console. the desktop and fleet services arrive with the first workstation apply.

   ```sh
   cd ~/Projects/dev-server
   ./workstation apply
   ```

   complete the actions printed by apply, including interactive enrollment. refer to the [desktop plan](desktop-install.md) for the headless, graphics and development checks.

## recovering from an interruption

if a mirror, package download or password prompt failed after the new filesystems were created, fix the reported problem, boot the same usb and use the resume path. it accepts an unfinished install with the matching disk serial and repo revision. it preserves the partition table and resumes setup on the existing filesystems.

```sh
bash /run/archiso/bootmnt/start-desktop --resume
```

if resume reports a missing marker, inspect the result of the original run. a successful install clears the marker and boots directly from the nvme. a failure during initial partitioning or formatting may require repeating the original install after checking the disk identity again. once the base system boots, repair package or enrollment failures from the installed system with `./workstation apply`.

the stock approach uses arch's partitioning, package, chroot and bootloader tools. the repository supplies the tower-specific choices. [installation guide](https://wiki.archlinux.org/title/Installation_guide) · [pacstrap](https://man.archlinux.org/man/pacstrap.8) · [systemd-boot](https://wiki.archlinux.org/title/Systemd-boot)
