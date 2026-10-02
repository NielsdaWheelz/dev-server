# macbook controller lacks github enrollment

problem: normal `./devbox apply` from the existing macbook operator cannot pass
its github enrollment check because `gh auth status -h github.com`
does not report an authenticated account.

impact: host reconciliation can complete, but the public command returns action
`2` until operator github enrollment can be inspected. this does not prevent
native ai adoption or change the server's existing ssh identity.

evidence (2026-10-02): final-source public devbox apply installed declared ubuntu
changes and returned `ACTION  GitHub enrollment: run: gh auth login -h github.com
&& ./devbox apply`. no ai action was emitted. existing docker/reboot deferrals
are independent. no account credentials were changed during qualification.

resolution: authenticate the intended operator with `gh auth login -h github.com`,
then rerun ordinary devbox apply. resolved when that command verifies the server
key enrollment without the github action. operator authentication is required;
installation code must not invent another account or bypass this check.
