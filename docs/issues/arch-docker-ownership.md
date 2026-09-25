# arch docker activation has two owners

problem: `packages_arch_reconcile_docker_activation` starts/restarts docker and
records its package activation; `personal_arch_configure_services` separately
enables/starts it. package reconciliation runs first.

impact: the package owner can abort apply before the personal owner reaches
its deliberate reboot deferral.

evidence (2026-09-25): disposable shell fixtures supplied an inactive docker,
pending reboot and failed service start. the package function exited 1;
`personal_arch_ensure_unit docker.service 1` returned the intended deferral 2.
locations: `lib/packages-arch.sh:25`, `lib/personal-arch.sh:126,612`, and the
package-before-personal order in `workstation_apply`.

follow-up: package code installs and reports packages. one personal-policy
function owns docker enablement, start/restart, container and reboot deferrals,
and activation recording. no shared cross-platform service workflow is needed.

resolved when: ordinary and upgrade paths use that one owner; pending reboot
defers consistently, running containers survive, and idle activation records
success only after the service is active.
