# pseudoCT repository instructions

`run_pseudo_CT.m` is the entry point. Use the profile selector or a canonical profile key. Supported profiles and dependencies are summarized in [`installation.md`](installation.md); researcher workflow and QC guidance are in the [User Guide](https://mscipio.github.io/pseudoCT_standalone/help/).

- Preserve MATLAB compatibility and profile-owned configuration; do not invent fallback resource paths. Runtime changes require explicit task approval and appropriate tests.
- Bounded historical comparisons are not universal parity. Users must inspect QC; evidence limitations are in [`scientific-notes.md`](scientific-notes.md).
- Keep researcher instructions in the User Guide and installation guidance in `installation.md`.
- Preserve release identity/history in `CHANGELOG.md`. Do not alter release artifacts or claim deployment/certification without authorization.
