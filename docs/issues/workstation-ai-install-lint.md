# workstation ai install lint

plain `shellcheck -x workstation` reports sc2119 at the intentional no-argument
`ai_install` call. its optional argument is a quota-publication flag; forwarding
workstation command arguments would change the call's meaning.

impact: the default lint command exits 1. this does not block provider launch.
the diagnostic reproduces on the unchanged `HEAD` version of workstation.
the memory-helper repair passes focused lint with this diagnostic excluded.

resolved when the intentional call is understood by the lint check and default
shellcheck passes without forwarding workstation arguments.
