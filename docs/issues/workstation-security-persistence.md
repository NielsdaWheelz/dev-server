# workstation boundary persistence is unqualified

problem: macbook's active network boundary has not been exercised through
tailscale reconnect or reboot; sleep/wake remains unqualified on both macbook
and arch.

evidence: on 2026-10-24 utc, fresh approved ssh and denied physical-interface
ingress passed in both address families; local and authorized peer workflows
survived. repeated native activation was inert on macbook. arch then rebooted
into `7.2.11` and passed fresh private ssh/8443, physical-lan denial, docker
publication controls and ssh forwarding in both address families. its reboot
persistence is established; the remaining transitions were not run.

impact: source and current runtime rules do not establish that those transitions
retain denial and restore approved access. testing them can interrupt active
work, so they need a suitable stopping point.

resolved when each remaining transition passes with fresh approved
ssh/skid access and physical-interface denial, including the re-established
tailscale interface and effective native rules. retain local recovery access.
