# devbox shellcheck baseline

problem: shellcheck reports SC2119 at the no-argument
`dev_server_tailscale_cli` call in `devbox`; the same observation occurs on the
unchanged original file.

impact: the full devbox shellcheck command exits nonzero; changed installer
libraries and workstation pass independently.

evidence: run `shellcheck -x devbox`. the installer change removes gateway
codex-source staging but does not change this call or its helper.

resolution: inspect the helper's optional argument contract and either make
this call explicit or document the intended no-argument use at that owner.
