# pseudoCT_standalone 3.1.0 — MLSC artifact provenance

This is a one-time provenance exception for one retained MLSC artifact. It
applies only when all three immutable SHA-256 anchors match:

- Executable: `0195a2c8e0d20adf766bc034d958d0bc45345c95f17e441cd42092cf6155c633`
- Launcher: `af30517193692001f30f4114cac6b00d5e3a41605f23a134c15be432dbdb97af`
- Build manifest: `62bb3472b8225178c89ff731d4c664a8636d775006c0903ccd5677de5aa090f5`

The manifest records MATLAB R2010b, MATLAB Compiler 4.14, MCR `[7 14]`,
`glnxa64`, and build date 2026-10-23. Its schema and resource schema remain
unchanged. All 11 inventoried package paths, byte sizes, and SHA-256 values,
the resource/launcher/executable hashes, and the extracted archive package
bytes remain subject to recomputation. The v3.1.0 release-source commit, tag,
and tree are resolved and recorded separately during release assembly; they
are not retroactively added to the original binary build manifest. No
R2026a Gate-A record is used for this artifact.

The original `source_commit` is retained and validated, and the recorded
`source_provenance_fingerprint` is preserved verbatim. The original dirty
source snapshot is not available, so that fingerprint cannot be independently
reconstructed. The exact association between this binary and job `10515471`
also cannot be independently verified.

As dataset-specific scientific acceptance only, the user-reported job
`10515471` succeeded with exit code 0 (one successful result, zero failures).
The user-supplied `att_map.nii` SHA-256 is
`1517efbe3fbb8e0f4df3fb3b2a4e40c387ba09fbcbac326496fe47cf8a6981ff`; for
that dataset it matched the results from `local-current`, `local-legacy`,
`mlsc-legacy`, and `mlsc-current-r2010b`. These scientific results are not
binary authentication and do not establish general equivalence or clinical
correctness.
