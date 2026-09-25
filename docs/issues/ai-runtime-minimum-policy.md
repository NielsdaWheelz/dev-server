# ai installation carries unexplained extra runtime minima

problem: `ai_require_codex_runtime` says codex requires node 24 and npm 11.17.0.
the installed pinned codex package declares node >=16; the installer no longer
uses the combined npm bundle's allowScripts policy from which the gate came.

impact: a historical package policy remains an additional installer constraint
and is described as an upstream codex requirement without current evidence.

evidence (2026-09-25): `lib/ai-tools.sh:3-23`, installed codex 0.155.1's
package.json engines, and git history at `39248fb`. current npm installation
uses `--ignore-scripts`. this does not prove every older runtime is supported.

follow-up: native package declarations own the chosen host runtime versions.
qualify whether any extra installer minimum remains necessary, remove obsolete
checks, and keep executable/version verification. do not downgrade host runtimes
or broaden supported platforms merely to reduce this check.

resolved when: each retained minimum has a present consumer requirement and a
single owner; otherwise installation relies on the declared host runtime.
