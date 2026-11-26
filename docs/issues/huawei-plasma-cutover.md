# huawei plasma cutover

the huawei mach-wx9 currently runs endeavouros and xfce. apply installs the
tower's plasma session and schedules its login manager for the next boot. the
laptop keeps its bootloader, kernel, wi-fi setup, user files and xfce session.
laptop power defaults keep ac jobs awake and suspend on battery after five
idle minutes. steam, tower graphics drivers and monitor configuration stay on
the tower.

the tailnet reported the laptop offline on 2026-11-26 and ssh timed out.
finish on the physical huawei with power and wi-fi available:

1. inventory the live checkout, display manager, graphics, network, audio and
   active work. apply and inspect its result before rebooting.
2. after reboot, log in to plasma and exercise wi-fi, audio, touchpad,
   brightness, battery and lid suspend/resume. verify a second apply and a
   fresh pinned ssh login. if needed, choose xfce in the login manager, or
   re-enable the previous display manager from the text console.
3. rename the hostname to `huawei` once the cutover is stable. check tailnet
   naming and pinned ssh access after the change. keep the logical `arch`
   memory and workstation target and the existing skid member identity.
   verify remote development and the native account status lines. memory
   enrollment remains tracked in [the activation issue](universal-memory-activation.md).
