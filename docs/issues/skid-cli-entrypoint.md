# required skid entry point was omitted during restoration

problem: the root operator reports `skid` absent on all three hosts. original's
fleet client config is also absent on devbox and arch.

impact: the documented no-argument fleet browser cannot be launched normally;
restoring the command alone does not supply the linux peer configuration.

evidence: `5bacd72` removed the required symlink for the phone-only product;
separation `94931a1` restored the original gateway without restoring that link.
the existing binary already implements the cli. its historical link target is
`../share/skidbladnir/current/skidbladnir`; no app release or receipt change is
needed. original's handoff incorrectly described the command as optional.

owners: dev-server restores the command's installation, protection, recovery
and removal; original's owner verifies the public entry points and retains
ownership of `scripts/fleet provision-clients`. the root operator coordinates
bounded link repair and private client provisioning. no live apply is part of
this source fix.

resolved when: reviewed source passes disposable lifecycle checks, and the
operator confirms all three login shells resolve `skid`, help/config admission
pass, and the required mode-`0600` three-peer configs exist with unchanged gateway/runtime
identities and provider state.
