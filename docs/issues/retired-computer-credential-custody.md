# retired computer credential custody is unverified

problem: network access for `skq-linux` and `niels-desktop` is retired, but their
offline copies of shared credentials cannot be inspected. one github ssh key
also remains unattributed.

evidence: github key `132067237`, fingerprint
`SHA256:oZVDNaiaPPQx6XSllDqXZmH3MYiH6f4EDRyIkpvOfmI`, was created
2025-09-22 and last used 2026-03-30. the owner could not identify it. active
computer and deployment ssh fingerprints are accounted for; there is no proof
this unknown key belongs to either retired computer.

impact: network removal does not establish that every credential previously
held by those computers is invalid. deleting the unknown key could break an
unidentified consumer, so preserve it pending attribution.

resolved when the github key is attributed and deliberately retained or revoked,
and offline shared-credential custody is established through inspection or
appropriate rotation with active consumers verified. hardware reachability and
key attribution remain the blockers. preserve the retired computers' data.
