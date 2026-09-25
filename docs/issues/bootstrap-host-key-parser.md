# bootstrap duplicates openssh's key parser

problem: `validate_new_host_key_candidate` manually decodes base64, parses ssh
binary string lengths, checks the embedded algorithm and counts ed25519 bytes,
after the real ssh client wrote the candidate during authenticated enrollment.

impact: roughly 70 lines duplicate native format validation without establishing
additional host trust.

evidence (2026-09-25): `devbox:402-473`. a disposable key fixture confirmed
`ssh-keygen -l -f` accepts a valid ed25519 known-hosts entry and rejects a
truncated encoded key. no real trust store or host was changed.

follow-up: use openssh for key syntax validation. keep the private candidate,
exact host alias and expected-key count, strict subsequent host verification,
preservation of unrelated entries, and atomic trust-store promotion.

resolved when: no local ssh binary-format parser remains and those enrollment
properties hold for valid, malformed, duplicate and wrong-host fixtures.
