# huawei clean installation

the owner chose to replace the huawei mach-wx9's current endeavouros setup
with stock arch and plasma. the prerequisite is a backup and confirmation of
the internal disk's identity. the laptop was offline when checked on 2026-11-26.

on the first boot from the internal nvme, the owner reported a hang with
`udev-worker` exiting with irqs disabled and `preempt_count 1`. the live usb
booted on this hardware with linux 7.2.11. the rehearsal installed linux 7.3.6
from the rolling mirror. the owner transcribed the second kernel oops from
the laptop on linux 7.3, including `idempotent_init_module`, `ioread32`,
and `nouveau(+)`, and reported no text login. test a single boot with
`module_blacklist=nouveau`; this is a hypothesis about the driver, since the
first oops is unavailable.

the next boot reached `huawei login:` with linux `7.3.6-arch1-1`. the owner
saw `nouveau` mmio read faults in `PRIVRING` at pci address `0000:01:00.0`.
the console photo shows `module_blackllist=nouveau` with an extra `l`, and
`lsmod` confirms both `nouveau` and `i915` are loaded. the successful boot
does not exercise the proposed workaround. verify a cold boot with the
correct spelling before choosing a durable boot policy.

the first workstation apply installed plasma and docker and queued an
intel-only boot entry with `bootctl set-oneshot`. the owner reported that
`sudo reboot` stopped at `Rebooting.` while the old kernel still had
`nouveau` loaded. the huawei stopped responding on the tailnet. the queued
entry passed a cold boot. ssh worked at the plasma greeter, the exact
`module_blacklist=nouveau` argument was present, and only `i915` was loaded.
the permanent entry then passed a standard warm reboot with the same driver
selection and reached the plasma greeter. docker and a skid terminal worked
from the mac before graphical login. the installer now declares the same
boot argument on the huawei.

the live laptop passed independent nvme boot, plasma login, wifi, pinned ssh,
skid and the native account status-line checks. the existing `arch` memory
identity is enrolled for the five signed-in accounts. [memory activation](universal-memory-activation.md)

the second apply configured the merged setup and deferred its authenticated
memory check while the central jarvis service was stopped for maintenance.
once it serves again, verify that the laptop's five enrolled capture lanes
still report active baselines.

remove the offline pre-reinstall `arch` device in the tailscale admin console.
verify that the new `huawei` device remains online and the old device is absent.

finish the physical checks in the [install procedure](../huawei-install.md).
check bluetooth and audio playback, touchpad, brightness, lid suspend and
resume, and the two power profiles.
