# local declarations repeat themselves in preflight checks

problem: dotfiles, personal arch/macos and parts of ai preflight duplicate file
lists solely to check regular source files. the common atomic installer checks
the same property at consumption. herdr's config validator repeats the entire
meaningful toml, and its unit parser repeats supervisor policy from the assets.

impact: changing one declaration requires editing a second representation;
these checks add no whole-host transaction, which the specification disclaims.

evidence (2026-09-25): the *_validate_declared_inputs helpers;
`lib/common.sh:403`; `herdr_config_valid` and `herdr_unit_environment` in
`lib/herdr.sh:125-183`.

follow-up: remove existence-only secondary file lists. let native parsers and
the checked-in assets own their formats/policy. retain actual cross-component
constraints: herdr must use the intended socket/config, avoid resuming agents,
and keep terminal lifetime independent of the gateway. its unmanaged socket,
snapshot and detection-state checks address real upstream behavior.

resolved when: an asset edit has one policy owner, invalid consumed input still
fails at the owning boundary, and genuine session/identity constraints remain.
