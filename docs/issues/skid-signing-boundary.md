# gateway apply inspects unrelated android signing credentials

problem: `skidbladnir_validate_present_credentials` and
`skidbladnir_validate_protected_paths` inspect android-signing.p12,
android-signing.properties and android-signing.password. a differing type or
mode blocks gateway apply although no installer operation consumes those files.

impact: android build state becomes an unrelated host-installation prerequisite.

evidence (2026-09-25): `lib/skidbladnir.sh:208-218,308-316`; repository search
found those two validation loops as their only code references.

follow-up: leave android signing files untouched and uninspected. retain
checks for bearer/machine identity files that the gateway actually consumes.

resolved when: gateway apply is independent of android signing file topology
and preserves every such file byte for byte.
