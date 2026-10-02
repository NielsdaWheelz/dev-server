# ghc package checks fail on arch's runtime-only installation

problem: after ordinary arch apply, `ghc-pkg check` exits `1` because the
package-owned `ghc-9.6.6` registration names compiler interfaces/library paths
that are absent. `ghc-libs 9.6.6-2` is installed; the compiler package is not.
its registration hook also warns about missing compiler settings and guesses
the native target. optional haddock documentation warnings are separate.

impact: ghc metadata verification is not clean. the current consumer,
`shellcheck 0.11.0`, runs and passed actual changed-source analysis; native ai
acceptance passed independently. no haskell compiler was added merely to silence
runtime-package warnings.

evidence (2026-10-02): ordinary `./workstation apply` on arch returned `0` after
its full 89-package upgrade. the compiler registration is owned by `ghc-libs`,
not an unowned local residue. other package files verified unchanged apart from
the registration hook's cache. `shellcheck -x lib/skid-provider.sh` passed from
the checkout root. private acceptance logs retain `ghc-pkg-check.txt`.

resolution: establish the native package's intended runtime/compiler split and
verify against that contract. if its runtime registrations are wrong, correct
upstream packaging rather than deleting owned metadata or inventing settings.
install the compiler only if the host needs haskell compilation. resolved when
package metadata checks pass for the declared installation or the package owner
confirms their compiler prerequisite and a suitable runtime check passes.
