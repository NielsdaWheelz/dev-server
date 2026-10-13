# codex installation discovery depends on account context

problem: upstream uses the selected `CODEX_HOME` to discover a shared standalone
installation and accepts inherited package-manager markers before executable
evidence. account identity and installation ownership are coupled.

impact: the planned local correction removes false package-manager routing, but
work accounts still cannot discover the standalone release owned under `.codex`.
shared maintenance must explicitly select the installation context.

evidence: [the 0.162.1 resolver](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/install-context/src/lib.rs#L120)
uses marker presence as a method override. its standalone discovery requires the
release directory to be beneath the selected home's standalone releases root.
[native qualification](../ai-native-installation-validation.md#upstream-native-qualification)
already records the work-account discovery limitation.

proposal: upstream should discover installation ownership independently of
account selection and accept manager provenance only when consistent with the
actual invocation. preserve valid native and package-manager installation modes.

scope: documented proposal only. no upstream contribution, local fork, release
dependency or extra installation is authorized by the local launch correction.

resolved when: released upstream behavior discovers a shared native installation
from personal/work account contexts and rejects inherited empty or nonempty
false manager markers while preserving genuine package-manager launches.
