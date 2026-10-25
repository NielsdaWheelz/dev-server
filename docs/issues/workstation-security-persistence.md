# macbook pf root hook was lost during os upgrade

problem: macos replaced `/etc/pf.conf` with its factory configuration during the
`27.0.1` upgrade. the owned anchor remained on disk but was absent from the live
root rules. the installed loader loaded the factory file without verifying its
root hook, then falsely reported success for an unreferenced owned anchor.

evidence: boot was 2026-10-25 05:38 utc; the root file changed 28 seconds later.
the 05:55 utc report showed only apple root anchors, despite the launch job's
single exit-zero run. its helper matched the reviewed prior source; helper,
anchor and plist files survived. the application firewall stayed enabled.

impact: an enabled pf and populated owned anchor do not enforce that anchor
unless the live root references it. prior lan-denial results do not qualify the
post-upgrade boundary.

source repair: the native loader now owns root-hook rendering and atomic
installation, preserves apple configuration, refuses a required reload over
foreign active root rules, and checks the live root hook before success.
isolated regression proof does not establish installed/runtime acceptance.

resolved when the reviewed repair is installed and fresh root-hook/owned-anchor
inspection, approved ssh/skid access and physical-interface denial pass in both
families. repeat activation must be inert, and reconnect/sleep/reboot must retain
that boundary. privileged activation and these transition checks remain pending;
retain local recovery access. arch's reboot and sleep/resume already passed.
