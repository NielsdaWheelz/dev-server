# fleet account recovery remains unverified

problem: the owner still needs to check/setup mfa and usable recovery for the
accounts controlling the fleet, source and hosting.

evidence: the 2026-10-24 utc api review found vercel mfa enabled, but usable
recovery and the other accounts' settings remain owner checks.

impact: network restrictions do not contain a takeover of the accounts that can
change them; lost account access can also defeat recovery.

owner checklist: confirm/enable a usable second factor, verify a fresh login and
retain accessible recovery material independently of the managed computers.

- [ ] [github security settings](https://github.com/settings/security): mfa and
  recovery codes. this tailnet uses github;
  [tailscale applies the identity provider's mfa](https://tailscale.com/docs/multifactor-auth)
  to authentication. verify a fresh tailscale login through github too.
- [ ] [cloudflare 2fa](https://developers.cloudflare.com/fundamentals/user-profiles/2fa/):
  verified email, second factor and backup codes.
- [ ] [hetzner 2fa](https://docs.hetzner.com/general/security-and-identify/two-factor-authentication/):
  second factor and retained recovery key.
- [ ] [vercel 2fa](https://vercel.com/docs/two-factor-authentication): confirm the
  enabled factor remains usable and recovery codes are accessible.

resolved when the owner verifies mfa and usable independent recovery for the
github/tailscale, cloudflare, hetzner and vercel accounts. keep recovery secrets
out of repository records; record only completion/status. host console login and
its tested local password are already confirmed; this concerns provider accounts.
