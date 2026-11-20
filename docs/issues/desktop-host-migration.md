# desktop host migration

the planned arch gaming and development desktop needs an explicit host
policy. `workstation_select_target` accepts only the owned huawei laptop on
linux. its arch policy assumes laptop hardware, xfce and its efi layout.
activation currently recognizes macbook, arch and devbox. the retired
desktop's old fleet identity has been revoked. [workstation entry point](../../workstation),
[arch policy](../../lib/personal-arch.sh), [activation](../../lib/activation.py),
[fleet security record](../fleet-security-spec.md).

enroll the refurbished desktop as a fresh device and add a host policy for
its chosen arch setup. inventory the development repositories, unpushed work,
account state and persistent data before moving them. nexus, jarvis and the
skid hub stay on the hetzner devbox.

close when ordinary desktop apply passes, remote access works after boot
without a graphical login, the required development state has transferred,
and a representative integration suite passes. macbook owns heavy
development until the handoff. [development placement](../desktop.md#development-placement).
