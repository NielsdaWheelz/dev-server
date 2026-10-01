# arch reboot activation

problem: arch's installed kernel is newer than the running one, so the kernel
upgrade still requires a reboot.

impact: arch runs its prior kernel without the matching installed module
directory until reboot; loading a module it has not already loaded can fail.
deploy deliberately does not reboot a running workstation, so this recurs after
each kernel upgrade.

evidence: arch last booted 2026-09-24 19:00 into `7.2.6-arch2-1`, clearing the
earlier `7.2.3` deferral. pacman upgraded `linux` to `7.2.7.arch1-1` on
2026-09-29. on 2026-10-01 the running kernel was still `7.2.6-arch2-1`, and
`/usr/lib/modules` held only `7.2.7-arch1-1` and `6.18.54-1-lts`. the earlier
desktop-session deferral has not been reported since 2026-09-17.

resolution: at a suitable stopping point, reboot arch. rerun apply and verify
the reboot deferral is gone.
