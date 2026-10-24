# native fleet patching is incomplete

problem: the macos minor update and one idle devbox pam-helper mapping remain
pending after native maintenance.

evidence from 2026-10-24 utc:

- macbook safari 27 and command line tools 26.6 are installed. a fresh native
  scan offers macos 26.7.1 and the major 27.0.1 upgrade. use the minor update in a
  future no-use window; active agents prevent a reboot now.
- devbox runs installed kernel `6.8.0-147`; scoped dbus/logind/user-bus/editor
  refresh completed, preserving eleven codex tasks and skid process identities.
  no failed units remain. only idle `sd-pam` retains a deleted-library mapping;
  refreshing its user-manager context is deferred until an all-agent no-use
  window. existing pgvector hold and cloud-init phasing remain unchanged.

impact: network restrictions do not install the offered macos fixes or refresh
the remaining idle helper's old library mapping.

resolved when the minor macos update and its reboot pass native update and
boundary checks, and the idle devbox helper mapping is refreshed in a safe
window with needrestart and private access rechecked. preserve active work and
existing native holds/phasing. arch and nexus native maintenance are complete.
