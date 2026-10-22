# docker disk allocation

problem: docker desktop's disk image grows without a useful ceiling. its
maximum (`DiskSizeMiB`) is 2 tib, and lowering the maximum deletes the existing
image, so the only cap available is a full docker reset.

impact: allocation competes directly with the host's free space. a reset would
discard every image, build cache and volume, including
`jarvis_jarvis-postgres`, the nexus release and runner volumes, and
`c3rh-pg-data`. doing that casually loses data; avoiding it indefinitely risks
filling the disk.

evidence:
- 2026-10-21: `Docker.raw` held about 246 gb, with 211 gib free on the host at
  the start of that day's nexus runs and 178 gib after them (nexus audit).
  docker reported 132.9 gb of volumes (103 gb of it the predecessor hockey
  store), 52.7 gb of images and 55.8 gb of build cache.
- 2026-10-22: `du -h` on
  `~/Library/Containers/com.docker.docker/Data/vms-data/Docker.raw` reported
  274 gb, and `/System/Volumes/Data` had 96 gib free. the hockey retention
  inspection had measured about 292 gb earlier, so allocation moves in both
  directions with ordinary work. other large holders at the
  same time: colima's disks 41 gb, `~/Library/Caches` 50 gb,
  `nexus-web-campaign-artifacts` 33 gb.
- docker's mac documentation
  (https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/#how-do-i-reduce-the-maximum-size-of-the-file)
  states that reducing the maximum deletes the existing disk image.

the hockey retention decision (delete its containers and volumes) and the
[macbook capacity plan](../macbook-capacity-plan.md) window's prunes are expected
to release well over 100 gb inside docker. how much returns to the host is
unmeasured, and freed blocks may return only after the guest trims them.

revisit: if allocation keeps rising after the window and nexus's image ownership
(d8) have landed, or host free space falls below 50 gib, plan a deliberate reset
with a lower maximum. that plan first inventories and exports every volume worth
keeping.

resolution: a day after the window, allocation is recorded and stable or
falling across a week of ordinary work.
