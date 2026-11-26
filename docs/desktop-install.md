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
its marker matches the disk. after the base system boots, complete private
restore before the first full apply. a package or enrollment failure is
recoverable by rerunning apply from the installed checkout.

## restore private workstation inputs

the usb embeds one checkout revision. prepare it from the intended revision
before the wipe. use the mac operator's public key so remote access is available
before the desktop packages or the tmux version check.

1. after console tailnet sign-in, retire the old device if this is a replacement.
   use the new device's actual ipv4 and ipv6 addresses in the existing private
   tailnet policy and mac firewall anchor. apply and verify the policies. retain
   other devices and grants. [network policies](fleet-security-spec.md#tailnet-policy)
2. point the mac's ssh alias at the enrolled replacement, using the operator's
   key and the `nnandal` account. check `ssh -G desktop` for its hostname,
   host key alias and known-hosts file. if it still pins the retired device,
   remove only that entry from the applicable file with
   `ssh-keygen -R "$lookup" -f "$known_hosts"`. connect once with
   `ssh -o StrictHostKeyChecking=ask -o HostKeyAlgorithms=ssh-ed25519 desktop true`.
   compare the sha256 fingerprint with the physical console before accepting.
3. on the mac, supply the complete four-file memory directory previously
   rendered for that enrolled host. point at the private backup itself. it
   contains `collector.json`, `collector.env`, `clients.env` and
   `profiles.json`. do not send the fleet declaration or bearer store.
   optionally pass the tower's saved kwin output configuration before first
   plasma login. an existing layout is preserved.

   ```sh
   scripts/restore-workstation-private desktop "$desktop_bundle" --display-layout "$saved_layout"
   ssh -t desktop 'cd ~/Projects/dev-server && ./workstation apply'
   ```

   omit `--display-layout` when there is no saved layout. the restore checks
   the existing ssh pin, matching owned hardware, operator and collector
   identity before sending private data. the remote checkout must include
   this helper at `~/Projects/dev-server`. an identical bundle can be supplied
   again. a conflicting enrollment requires separate review. for the owned
   laptop, use `scripts/restore-workstation-private arch "$arch_bundle"` with
   its own credentials and configured remote access. if a host has no approved
   bundle, continue with the ordinary apply and leave memory enrollment pending.
   use `--ssh-host ALIAS`
   for a different pinned ssh alias.
4. for a replacement, identify its superseded skid member with `skid status`
   on an enrolled computer and retire that specific id with
   `skid remove DEVICE_ID`. issue a new invitation with `skid connect`, use
   `skid join --name desktop` on the tower, then run `skid connect` there
   once. restore the existing memory bundle only to its authorized logical
   host. a genuinely new machine or changed sharing scope needs a separate
   authorization. a routine reinstall leaves the central jarvis history and
   approved grants in place.

## enroll and verify

1. verify the [network, skid and memory enrollment](../README.md#enroll-the-desktop).
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
