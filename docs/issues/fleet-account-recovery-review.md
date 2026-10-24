# fleet account recovery remains unverified

problem: current api access does not establish mfa and usable recovery for all
accounts controlling the fleet, source and hosting.

evidence: the 2026-10-24 utc read-only review found vercel mfa enabled.
github's authenticated-user response did not expose a usable mfa flag;
tailscale uses that github identity. the account-scoped cloudflare token cannot
read the user security profile (403). hetzner's project api access establishes
infrastructure access, not account mfa or recovery. saved recovery material was
not inspected for any of these accounts.

impact: network restrictions do not contain a takeover of the accounts that can
change them; lost account access can also defeat recovery. these gaps do not
prove mfa is disabled or recovery material is missing.

resolved when the owner verifies mfa and usable independent recovery for the
github/tailscale, cloudflare, hetzner and vercel accounts. keep recovery secrets
out of repository records. host console login and its tested local password
are already confirmed; this issue concerns provider accounts.
