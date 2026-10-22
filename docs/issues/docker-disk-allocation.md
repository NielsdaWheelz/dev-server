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

decision (operator, 2026-10-22): everything left in docker is disposable,
jarvis's local postgres included. the [macbook capacity plan](../macbook-capacity-plan.md)
window resets docker with a 128 gib maximum.

resolution: after the reset, the maximum is 128 gib. allocation recorded a day
later, and again after a week of ordinary nexus work, stays below the cap with
builds succeeding. if builds hit the cap, the nexus image ownership (d8) has not
held; reopen that, not the cap.
