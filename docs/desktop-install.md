# desktop wipe, install and recovery

the tower runs stock arch for development and steam. the installer owns the
disk layout and base system. ordinary workstation apply owns packages and
services. hetzner hosts jarvis, nexus and the skid hub.

## prepare the usb on the mac

back up files, game saves, unpushed work and anything needed for account
recovery. record the intended internal nvme's model, serial and capacity
privately. disconnect backup drives before booting the installer.

use an empty, mounted fat32 usb stick and python 3.11 or newer. obtain the
official arch x86-64 iso, verify its signature and use the sha256 from the
release page. select a local branch containing the intended installer.
the command copies a uefi boot environment and a self-contained git bundle.
the optional public key authorizes ssh access on the installed system.
[arch downloads](https://archlinux.org/download/) ·
[fat32 uefi method](https://wiki.archlinux.org/title/USB_flash_installation_medium#UEFI_only)

```sh
scripts/prepare-desktop-usb "$iso" "$official_sha256" "$usb_mount" "$branch" --public-key "$HOME/.ssh/id_ed25519.pub"
```

eject the usb after verification finishes. connect ethernet at the tower.

## install and recover

follow the [console instructions](desktop-bootstrap.md) to boot the usb,
identify the disk, authorize erasure and set the local password. the
installer replaces all partitions on the selected disk with a 1 gib fat32
efi partition and an unencrypted ext4 root. systemd-boot loads the stock
kernel. the installed checkout matches the bundled revision.

an interrupted base install can resume from the same usb and revision when
its marker matches the disk. after the base system boots, run
`./workstation apply` from the installed checkout. a package or enrollment
failure at that stage is recoverable by rerunning apply. review any requested
logout, reboot or interactive sign-in.

## enroll and verify

1. follow the [network, skid and memory enrollment](../README.md#enroll-the-desktop).
   keep the evaluated network policies, provider credentials, memory declaration
   and generated bundles in private storage. restore user files from backups.
2. reboot to the graphical login screen. before logging in, verify ssh,
   docker and a remote skid session. ask jarvis for a desktop worker and
   verify its handle opens on the tower.
3. in plasma, identify the primary display, check simultaneous display modes
   and select the desired audio output. confirm nvidia acceleration and steam
   playback in a representative game. [display checks](issues/desktop-display-links.md)
4. verify a second ordinary apply preserves the installation and enrollment.
   run a representative development integration suite before handing over
   heavy work. [development handoff](issues/desktop-host-migration.md)
