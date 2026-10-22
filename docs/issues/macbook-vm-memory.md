# macbook vm memory

problem: two linux vms reserve 36 of the macbook's 64 gib: docker desktop at
24 gib, and colima profile `c3nt` at 12 gib. guest page cache is not returned to
the host, so idle guest memory becomes host compressor and swap load.

impact: interactive work slows under memory pressure, and the agents, which run
at skid's clamped priority, lose arbitration first. the host reached pressure
warning while a nexus campaign cycle and two lab stacks were running.

evidence (2026-10-21, 15:28–16:10 local): `kern.memorystatus_vm_pressure_level`
2; `top` reported 63 gib used, 30 gib of it compressor, and 113 mib unused;
`vm.swapusage` 4.25/5 gib. docker desktop's vm (pid 87491) had a 24 gib footprint
(5.3 gib resident) with 14 containers using under 1 gib together. the colima vm
(pid 40833) had a 10 gib footprint and averaged above one core for 1.5 hours.
`settings-store.json` contained `MemoryMiB: 24576`; a nexus release-runner
session raised it from the 8 gib default on 2026-09-05.

progress (2026-10-22): d1 and d2's sizing are applied. nexus deleted `c3nt` on
2026-10-21, and docker has run with 8 gib and 8 cpus since 09:59 (nexus-web
#751). the pressure level read 1 at 12:12 with labs idle. neither check below
has run since.

resolution: the [macbook capacity plan](../macbook-capacity-plan.md) window applies
d1 and d2. the pressure level then stays 1 through one campaign cycle plus
interactive work, and two ordinary nexus lab invocations complete concurrently
with 8 gib memory and 8 cpus.
