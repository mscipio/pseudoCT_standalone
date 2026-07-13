# Delta for entrypoint-divergence-diagnostics

## ADDED Requirements

### Requirement: Diagnostic Reusability and Documentation

Diagnostic scripts (`diff_entrypoint_runs.m`, `compare_nifti_data.m`, `compare_hash_strings.m`, `restart_from_repos_checkpoint.m`, `sweep_smoothing_fwhm.m`, `normalized_2_att_map.m`, `pseudo_ct_princomp_legacy.m`) MUST remain tracked. Each MUST include a header marking it as an investigation tool referencing this change. They SHALL be listed in CHANGELOG.md as reusable diagnostic tooling.

#### Scenario: Diagnostic identifiable as investigation tool

- GIVEN any listed diagnostic script
- WHEN read
- THEN its header SHALL state it is an investigation tool referencing `investigation-cleanup-release`

### Requirement: Investigation Artifact Classification

Generated artifacts MUST be classified as Keep (tracked), Remove (deleted), or Ignore (gitignored) before release tagging. Remove: transient/accidental (`package-lock.json`, cookbook scripts, stray archive report). Ignore: large/reproducible (`spm8-dan/`, sweep outputs, test data variants). Keep: reusable diagnostics, PCA shim, TODO.md.

#### Scenario: Classification applied before tag

- GIVEN investigation artifacts in the workspace
- WHEN classification runs
- THEN each untracked artifact MUST be assigned Keep, Remove, or Ignore
- AND Remove artifacts MUST be deleted
- AND Ignore artifacts MUST have `.gitignore` entries

#### Scenario: TODO.md preserved

- GIVEN `TODO.md` with operator notes
- WHEN classification runs
- THEN it MUST be classified Keep and MUST NOT be deleted
