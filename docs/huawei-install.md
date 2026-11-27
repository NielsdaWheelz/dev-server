# clean install on the huawei

1. back up local data and unpushed work. on the existing system, record the
   internal nvme's model, serial and size with `lsblk -d -o PATH,MODEL,SERIAL,SIZE,TRAN`.
   disconnect any backup disks and plug in the charger. prepare the same fat32
   installer usb as the tower using the huawei-capable revision and the mac's
   operator public key. [prepare the usb](desktop-install.md#prepare-the-usb-on-the-mac)
2. use `F12` at power-on to choose the uefi usb and start the arch live system.
   if the official image is refused, check secure boot in the `F2` firmware
   settings. [huawei boot menu](https://consumer.huawei.com/en/support/content/en-us00695968/)
3. if using wifi, run `iwctl device list` at the live console. use the wifi
   device shown in the list in place of `wlan0`. the passphrase stays at the
   console. [arch live networking](https://wiki.archlinux.org/title/Installation_guide#Connect_to_the_internet)

   ```sh
   iwctl station wlan0 scan
   iwctl station wlan0 get-networks
   iwctl station wlan0 connect "your wifi network"
   ```

4. run the installer. match the internal nvme against the backup inventory
   before typing its path and the requested erase confirmation. the installer
   replaces every partition with a 1 gib efi partition and an unencrypted
   ext4 root, installs stock arch, and names the host `huawei`. set the local
   password for `nnandal` when prompted. resume an interrupted install with
   the same usb and `--huawei --resume`.

   ```sh
   bash /run/archiso/bootmnt/start-desktop --huawei
   ```

5. shut down, remove the usb, boot the internal drive and log in as `nnandal`.
   reconnect wifi in `sudo nmtui`, using **activate a connection**. enroll the
   replacement device with `sudo tailscale up` and print its ssh fingerprint
   with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.
6. verify the new ssh fingerprint at the console before accepting the new key
   on the mac. update the private tailnet addresses and ssh alias, then follow
   the [private restore procedure](desktop-install.md#restore-private-workstation-inputs)
   for any approved `arch` enrollment bundle. use `--ssh-host huawei` if the
   mac alias changed. run `cd ~/Projects/dev-server && ./workstation apply`
   on the laptop or over a pinned ssh connection with a tty. a reboot starts
   the plasma login. finish any provider or skid sign-ins and confirm wifi,
   sleep/resume, sound and the dev tools. [reinstall checks](issues/huawei-plasma-reinstall.md)
