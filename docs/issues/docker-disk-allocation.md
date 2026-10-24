# docker disk allocation

problem: docker desktop's disk image has a 2 tib maximum, so image and build
cache growth can consume the host disk unchecked. lowering the maximum deletes
the existing image, so a cap is only available as a full docker reset.

impact: allocation competes directly with the host's free space. on 2026-10-22
host free space fell to 96 gib before hockey's store was deleted.

evidence:
- 2026-10-21: `Docker.raw` was about 246 gb. docker reported 132.9 gb of
  volumes (103 gb of it the predecessor hockey store), 52.7 gb of images and
  55.8 gb of build cache.
- 2026-10-22, before the hockey deletion: 274 gb allocated, 96 gib free on
  `/System/Volumes/Data`. the hockey retention inspection had measured about
  292 gb earlier, so allocation moves in both directions with ordinary work.
- 2026-10-22, after hockey deleted its nine containers and volumes: 178 gb
  allocated, 191 gib free. freed guest blocks do return to the host.
- docker then held 244 images (75 gb), 92 gb of build cache (20 gb
  reclaimable) and 28 gb of volumes. within a day, images had grown 22 gb and
  build cache 36 gb during nexus image work.
- docker's mac documentation
  (https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/#how-do-i-reduce-the-maximum-size-of-the-file)
  states that reducing the maximum deletes the existing disk image.
- 2026-10-22 13:13 local, the reset: nexus's storage cleanup had removed every
  container, volume and custom network, leaving 24 images (19.6 gb) and 22.7 gb
  of build cache in 43 gb allocated, with 399 gib free. after: `Docker.raw` held
  6.5 mb of a 128 gib maximum, and 444 gib was free.
- 2026-10-23 23:45 local, about 34 hours later, after the cold rebuild and the
  six-lab qualification's builds (five labs were live at 23:39): 48 gib
  allocated, 387 gib free. docker held 31 images (17.6 gb, 9.4 gb reclaimable)
  and 35.8 gb of build cache (20.4 gb reclaimable). a repeat of that day's rate
  would reach the cap in about two more days.
- the builder's gc policy (`docker buildx inspect default`, engine 29.7.2,
  buildkit v0.32.2) carries `~/.docker/daemon.json`'s `defaultKeepStorage: 20GB`
  as `Reserved Space: 20GiB` on its three general rules, with no `Max Used
  Space` or `Min Free Space`. buildkit's reserved space is a floor gc keeps, not
  a ceiling, so build cache above 20 gb is within policy. afaict nothing short
  of the 128 gib maximum bounds it.

decision (operator, 2026-10-22): everything left in docker is disposable,
jarvis's local postgres included. the [macbook capacity plan](../macbook-capacity-plan.md)
window resets docker with a 128 gib maximum.

resolution: the maximum is 128 gib since the reset. allocation recorded after a
week of ordinary nexus work stays below the cap with builds succeeding. if builds
hit the cap, read `docker system df` first. build cache over the cap is gc
without a ceiling: set `defaultMaxUsedSpace` under `builder.gc` in
`~/.docker/daemon.json` and restart docker. images over it mean the nexus image
ownership (d8) has not held; reopen that, not the cap.
