# phone-to-arch terminal qualification is incomplete

problem: an existing arch terminal was not opened from the phone after the
tailnet policy and workstation changes.

evidence: on 2026-10-24 utc, the phone opened existing macbook/devbox terminals.
arch's fresh management api passed, but the selected phone roster offered no
arch terminal. the phone-to-arch terminal journey remains NOT_RUN.

impact: allowed transport and computer-to-computer checks do not establish that
this phone workflow works. this is an acceptance gap, not an observed denial.

resolved when the phone's normal client opens an existing arch terminal under
the restricted policy, without re-pairing or changing existing workspace state.
