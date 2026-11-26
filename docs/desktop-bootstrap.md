# installing the tower from the prepared usb

the usb contains the official arch live environment, `start-desktop`, and a git bundle of the workstation configuration. the bundle supplies the checkout. installing arch packages requires ethernet and an internet connection.

1. disconnect the backup drives. on the tower, tap `F12` and select the uefi entry for the usb. boot the arch installation medium. if the firmware refuses the official image, switch secure boot off.
2. at the live root prompt, run the launcher below. it loads the bundled revision and displays the attached disks. match the internal nvme's model, serial and capacity against the drive you intend to erase. enter its device path. review the displayed disk and partition layout before typing the requested confirmation.

   ```sh
   bash /run/archiso/bootmnt/start-desktop
   ```

3. the installer creates a 1 gib efi partition and an unencrypted ext4 root, installs stock arch and the boot loader, and copies its own repo revision to `/home/nnandal/Projects/dev-server`. if the usb carries `operator.pub`, the installer shows the key fingerprint and authorizes that public key for ssh on the new account. when prompted, enter the password for `nnandal` twice. keep it local.
4. when the installer finishes, shut down, remove the usb, boot the nvme and log in as `nnandal` at the text console. the base install includes tailscale, the firewall and key-only openssh. physical network ingress is closed. ssh is enabled at boot when the usb supplied the operator public key. if you omitted it, authorize the intended public key at the console first and then run `sudo systemctl enable --now sshd`.
5. sign in to the tailnet and print the tower's addresses and ssh host fingerprint.

   ```sh
   sudo tailscale up
   sudo tailscale set --operator="$USER"
   tailscale ip -4
   tailscale ip -6
   ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
   ```

6. on the mac, follow the [private restore procedure](desktop-install.md#restore-private-workstation-inputs). it verifies the new ssh key and supplies the inputs before the first full apply. then run the following on the tower. a mac operator can run the same command in a pinned ssh session with a tty.

   ```sh
   cd ~/Projects/dev-server
   ./workstation apply
   ```

   complete the actions printed by apply, including account sign-ins, skid enrollment and the requested reboot.

## recovering from an interruption

if a mirror, package download or password prompt failed after the new filesystems were created, fix the reported problem, boot the same usb and use the resume path. it accepts an unfinished install with the matching disk serial and repo revision. it preserves the partition table and resumes setup on the existing filesystems.

```sh
bash /run/archiso/bootmnt/start-desktop --resume
```

if resume reports a missing marker, inspect the result of the original run. a successful install clears the marker and boots directly from the nvme. a failure during initial partitioning or formatting may require repeating the original install after checking the disk identity again. once the base system boots, repair package or enrollment failures from the installed system with `./workstation apply`.

the stock approach uses arch's partitioning, package, chroot and bootloader tools. the repository supplies the tower-specific choices. [installation guide](https://wiki.archlinux.org/title/Installation_guide) · [pacstrap](https://man.archlinux.org/man/pacstrap.8) · [systemd-boot](https://wiki.archlinux.org/title/Systemd-boot)
