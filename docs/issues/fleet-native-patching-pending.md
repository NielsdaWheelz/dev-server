# native fleet patching is incomplete

problem: macos maintenance and some devbox process restarts remain pending after
the fleet's native package updates.

evidence from 2026-10-24 utc:

- macbook safari 27 and command line tools 26.6 are installed. a fresh native
  scan offers macos 26.7.1 and the major 27.0.1 upgrade. use the minor update in a
  future no-use window; active agents prevent a reboot now.
- devbox completed native apt maintenance and runs the installed `6.8.0-147`
  kernel. needrestart still reports dbus/logind and existing ide/user sessions;
  eleven active codex tasks were preserved. the existing pgvector hold and
  native cloud-init phasing were retained. rootless docker was restarted with
  its container identities preserved; rootful docker/containerd remain inactive.
- arch completed repository/declared aur updates and rebooted into `7.2.11`;
  fresh repository updates and failed-unit lists are empty.

impact: network restrictions do not install the offered macos fixes or activate
updated libraries still loaded by deferred devbox processes.

resolved when the minor macos update and its reboot pass native update and
boundary checks, and the deferred devbox services/sessions restart at a safe
stopping point with needrestart rechecked. preserve active work and existing
native holds/phasing. [devbox disk headroom](devbox-disk-headroom.md) is a separate
capacity follow-up, not a failed maintenance gate. nexus maintenance is complete
and recorded in its own repository.
