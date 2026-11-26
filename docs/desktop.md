# desktop development handoff

## development placement

run heavy development on `macbook` pending the desktop handoff. wait while the
mac is unavailable. the hetzner devbox serves production. existing release
pipelines keep their own placement. the desktop takes this work only after its
skid access and representative integration suite pass.

start a new detached rehearsal on the mac with python 3.11+, git, and the local
docker desktop engine available:

```sh
scripts/rehearse-worktree /path/to/repo REV /private/persistent/new-run \
  --expect result.json -- command arg
```

use a revision reachable from a retained git ref. choose a new directory
under existing private persistent storage. the command
receives its path as `REHEARSAL_EVIDENCE_DIR`. finish promised files there and
close the files before exiting. the command owns fixture teardown, including
ignored outputs, temporary databases, and stopped containers. remove only paths
the check created and keep the observed check exit status. use the managed
mac's docker desktop engine for containers. pass ordinary argv and keep secrets
in private configuration. the receipt includes the command arguments.

read `receipt.json` after the run. it gives the exact commit, command exit or
signal, verified evidence paths and hashes, and checkout disposition. a cleanup
failure exits nonzero even when the check passed. report the two outcomes
separately. before sending a report, use a private locator its intended reader
can reopen and verify. an interrupted run retains the checkout.

retained scratch lives under `~/.local/state/dev-server/rehearsals`, outside the
os's temporary-file cleanup. for recovery after a hard kill, use the printed
scratch and evidence paths.
acquire the exclusive scratch-directory lock and keep it open while inspecting
and removing the checkout:

```sh
python3 -c 'import fcntl, os, subprocess, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
raise SystemExit(subprocess.call([os.environ["SHELL"]], pass_fds=(fd,)))' "$scratch"
```

from that shell reopen and hash the files promised in `receipt.json`,
check git status including ignored files and check reachability of head and its
whole reflog from named refs. inspect `lsof -nP +D "$scratch" +D "$evidence"` for open users
apart from the recovery lock holders. inspect binds in all containers, including
stopped ones, on `docker --context desktop-linux`. include local volumes whose
driver binds a host path. preserve changed files or
unreachable commits first. when the checks are complete and clear, use ordinary
`git worktree remove "$scratch/checkout"` from the original repository and
`rmdir "$scratch"`. leave the evidence directory in place.

existing hetzner scratch may contain local work, live users, or the only copy
of a result. use the read-only inventory and inspect each root before proposing
separate disposal. keep uncertain roots.

## desktop refurbishment

the november 16 plan uses one bare-metal arch installation for steam/proton
gaming and remote development. the desktop may be offline during maintenance.
leave idle suspend off and start development services at boot. nexus and
jarvis run on the hetzner devbox. the existing skid hub stays there.

the [desktop wipe, install and recovery plan](desktop-install.md) covers the
fresh arch installation, repeatable workstation apply and fleet enrollment.

the main components date from about 2019. the pc was disassembled at
inventory. identify disks and back up existing data before repartitioning.

| part | recorded inventory |
|---|---|
| processor and board | intel i7-9700k, eight cores and eight threads, lga1151. gigabyte z390 aorus ultra, full atx, three m.2 slots |
| memory | corsair dominator platinum `CMD32GX4M2C3200C16`, two 16 gb ddr4-3200 cl16 udimms |
| graphics | evga rtx 2080 ftw3 ultra gaming, 8 gb, 302 mm long, 2.75 slots, two 8-pin pcie power sockets. [evga specifications](https://www.bhphotovideo.com/lit_files/439156.pdf) |
| power | nzxt e650, 650 w gold, 150 mm long, modular atx |
| cooling | nzxt kraken x62 `RL-KRX62-02`, 280 mm radiator with two aer p140 fans |
| spare fans | six noctua nf-a12x25 flx, 120 mm, three-pin dc speed control |
| displays | two 27-inch dell s2725qc ips monitors, 3840 × 2160, up to 120 hz |
| storage | the installer requires a whole internal nvme drive. record its model, serial and capacity before selecting it |

in plasma display configuration, identify the physical screens, arrange them
and select the primary display. the volume menu can switch between monitor
and television outputs. for analog headphones or speakers, select the
built-in audio device and its analog stereo profile in sound settings.

check for the original e650 modular cables, x62 backplate, standoffs, radiator
screws and pump leads. assembly needs a duster, paste, a ph2 screwdriver, a
ph1 for the m.2 screws and an installation usb stick of at least 8 gb. the
3.5 g pack of nt-h2 includes three cleaning wipes. dry lint-free wipes and
90–99% isopropyl alcohol are another option. check ethernet and display cable
lengths against the floor placement and buy only the missing parts.
[nt-h2 package contents](https://www.noctua.at/en/products/nt-h2-3-5g/specifications).

## case and assembly

the november plan preferred the standard lian li lancool 207. confirm the
purchase and fit before ordering accessories. the aim is a compact, affordable
full-atx case. use a raised hard surface for floor placement.

| fit | lancool 207 | jonsbo d41 mesh |
|---|---|---|
| external (w × h × d) | 219 × 456 × 455.6 mm, 45.5 l | 205 × 407 × 452 mm, 37.7 l |
| board | microatx or full atx up to 244 mm wide | microatx or full atx |
| psu | under 160 mm. 140–150 mm leaves more cable room | up to 220 mm in some layouts. shorter units leave more gpu clearance |
| gpu length | up to 375 mm | up to 400 mm with a 150 mm psu at level 1, a top 240/280 mm radiator and gpu in the second case slot. with a 150 mm psu and top 360 mm radiator, the second-slot layouts allow 342–360 mm |
| top radiator | 280 mm with assembly thickness up to 60 mm | 280 mm, subject to board and ram clearance |
| air cooler height | 180 mm | 168 mm |

the d41 saves about 17% in volume and 7% in floor area. the 207 had the
stronger controlled cooling evidence and easier sourcing at the november 9
check. that search found no confirmed d41 stock at the u.s. sellers checked.
the 207 has tight psu cabling and its optional front filter leaves the lower
side and rear intake exposed. [207 cooling and build review](https://gamersnexus.net/cases/lian-li-lancool-207-airflow-case-review-cable-management-build-quality-benchmarks),
[d41 specification](https://www.jonsbo.com/en/products/D41MESHBlack.html).

the kraken assembly is about 56 mm thick. dry-fit the ram, board heatsinks and
original psu cables before closing the panels. check gpu thickness, clearance
above the bottom fans and side-panel space for the power plug. the 207 also
has two 2.5/3.5-inch drive mounts. for a replacement board, check the gpu slot
position against the d41 layout table. both cases list standard atx layouts.
check wider or rear-connector boards individually. [lancool specification](https://lian-li.com/product/lancool-207/),
[207 manual](https://drive.google.com/file/d/1IQJX1M_nSX2fXlNHxH3dC1aGMd5NvP2a/view),
[d41 manual, printed page 9](https://www.jonsbo.com/Upfiles/down/D41_User%E2%80%99s_Manual.pdf),
[case fit issue](issues/desktop-case-fit.md).

for the 207, start with the supplied two 140 mm front and two 120 mm lower
intakes, the kraken fans exhausting through the top and an empty rear mount.
the 120 mm noctuas fit the lower or rear positions. the 207 front mounts and
x62 radiator take 140 mm fans. for the d41, use three 120 mm noctuas as
bottom intake, one as rear exhaust and the two kraken fans as top exhaust.
check floor and rear clearance before mounting. use dc control for the
noctuas and compare load temperatures and noise with the case closed.
[assembly and fan tuning](jonsbo-d41-walkthrough.html).

hold fan blades during cleaning and leave the psu enclosure closed. clean the
cpu and cold plate, repaste and mount the existing cooler evenly. the kraken's
usb controls are available through liquidctl. check pump operation after a
reboot and under sustained load. reuse the working components. confirm memory
detection and stability, disk health and both monitor links under arch.
[liquidctl kraken guide](https://github.com/liquidctl/liquidctl/blob/main/docs/kraken-x2-m2-guide.md),
[display connections](issues/desktop-display-links.md).

## development handoff and upgrades

use kde plasma/wayland, steam/proton, ssh, tailscale and skid. use one
worktree per agent and one compose project per development stack on one docker
engine. start with a single heavy integration run and pause it while gaming
if resources compete. complete the [development handoff](issues/desktop-host-migration.md)
before moving those workloads.

the desktop manifest selects the stock linux kernel, `nvidia-open`,
`nvidia-utils` and `lib32-nvidia-utils` for steam. verify that the installed
kernel loaded the matching driver. [package manifest](../packages/desktop.pacman.txt)

use the witcher 3, total war and the blood of dawnwalker as representative
gaming workloads. measure gameplay on the existing gpu at acceptable settings.
the monitors' 4k/120 hz link test measures display capability. measure game
frame rates separately, adjusting resolution and upscaling before replacing
the gpu. for development, measure the actual build and integration suite.

upgrade against measured limits. keep the nvme drive for active repositories,
databases and games if its health and space suffice. use the external drives
for bulk data. sustained paging or out-of-memory failures justify evaluating
64 gb with two more 16 gb dimms. the board has four slots. separately
purchased kits need a combined stability check, even with matching
specifications. lower memory speed if necessary. insufficient ssd space or
measured storage stalls justify a larger drive. for saturated builds, reduce
concurrency before replacing the cpu and board. short psus also exist at
higher wattages. for example, the 140 mm seasonic focus gx atx 3.1 range
extends to 1000 w. [board specifications](https://www.gigabyte.com/Motherboard/Z390-AORUS-ULTRA-rev-10/sp),
[seasonic specifications](https://seasonic.com/focus-gx-atx-3/),
[corsair's guidance on mixing kits](https://www.corsair.com/us/en/explorer/diy-builder/memory/can-i-mix-corsair-memory-kits/).

size a future heavy-development workstation independently. the planning target
is about 15 agents and heavy tests, with 256–512 gb ecc, 24–32 or more cores
and one or two high-vram nvidia gpus. the platform is open. the current
non-ecc ddr4 udimms require the right memory generation and module type.

| platform example | memory fit |
|---|---|
| intel 12th–14th gen on a d4 board | the existing udimms may work with a supported cpu and kit. [asus z790-plus d4](https://www.asus.com/motherboards-components/motherboards/tuf-gaming/tuf-gaming-z790-plus-d4/techspec/) |
| amd am5 or intel core ultra desktop series 2 | both use ddr5. [amd am5](https://www.amd.com/en/products/processors/chipsets/am5.html), [intel desktop series 2](https://www.intel.com/content/www/us/en/support/articles/000099656/processors.html) |
| trx50 or wrx90 workstation | ddr5 registered dimms. [memory population rules](https://www.kingston.com/en/memory/server-memory/memory-population-rules-wrx90-trx50) |
| epyc 7003 workstation | uses ddr4 server dimms. the existing unbuffered kit is incompatible. [amd memory guide](https://docs.amd.com/api/khub/documents/0bglRXRnwmLeDr6L0vSZVA/content) |
| trx40 workstation | a compatible non-ecc udimm can work. the planned workstation needs ecc. [asus trx40 memory support](https://www.asus.com/sg/motherboards-components/motherboards/prime/prime-trx40-pro/techspec/) |

extra ddr4 should earn its cost while the gaming desktop uses it. compare the
whole cpu, board and memory cost when changing platforms. budget for the
workstation's own memory. the desktop can stay in service for gaming after
development moves.
