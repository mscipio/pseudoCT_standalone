# entrypoint-divergence-diagnostics Specification

## Purpose

Tooling to preserve and compare local-vs-Launchpad pseudo-CT intermediates so an operator can locate the first divergent artifact. Does NOT fix root causes — enables the investigation.

## Requirements

### Requirement: Temp Preservation Config

The system MUST support `keep_temp_files` (`'Yes'`|`'No'`, default `'No'`) in both `defaults_pseudo_CT.m` and `defaults_pseudo_CT_launchpad.m`. The env var `PSEUDOCT_KEEP_TMP=1` MUST override to `'Yes'` without file edits.

#### Scenario: Enabling via defaults

- GIVEN `keep_temp_files = 'Yes'` in the active defaults
- WHEN the pipeline completes successfully
- THEN `MR_PET/tmp/` MUST NOT be deleted

#### Scenario: Default production behavior unchanged

- GIVEN `keep_temp_files = 'No'` and `PSEUDOCT_KEEP_TMP` unset
- WHEN the pipeline completes
- THEN `MR_PET/tmp/` MUST be removed as before

### Requirement: Cleanup Gating — Local Entry

When `keep_temp_files` resolves to `'Yes'`, `run_pseudo_CT_local` MUST skip `rmdir(temp_working_dir, 's')`.

#### Scenario: Local rmdir suppressed

- GIVEN `keep_temp_files = 'Yes'` and promotion succeeds
- THEN the `rmdir` MUST NOT execute

### Requirement: Cleanup Gating — Launchpad Entry

When `keep_temp_files` resolves to `'Yes'`, `run_pseudo_CT_launchpad` MUST skip its `rmdir` block AND pass `keep_tmp=1` to `batch_pseudo_CT_launchpad`.

#### Scenario: Launchpad dual cleanup suppressed

- GIVEN `keep_temp_files = 'Yes'`
- THEN local `rmdir` MUST NOT execute
- AND `batch_pseudo_CT_launchpad` MUST receive `keep_tmp=1`

### Requirement: Cluster-Side Cleanup Gate

`batch_pseudo_CT_launchpad` MUST accept name-value pair `'keep_tmp'` (0|1, default 0). When 1, the `ssh2_command('rm -rf %s', lc_path)` after `scp_get` MUST NOT execute.

#### Scenario: Cluster scratch preserved

- GIVEN `keep_tmp=1`
- AND the SSH job succeeds
- AFTER `scp_get` completes
- THEN the cluster scratch folder MUST remain on disk

### Requirement: Entrypoint Diff Comparator

`scripts/diff_entrypoint_runs.m` MUST accept two directory paths (local, Launchpad) and produce a structured comparison report listing each file as IDENTICAL, DIVERGENT, EXPECTED_DIFF, LOCAL_ONLY, or LAUNCHPAD_ONLY.

#### Scenario: Identical and divergent NIfTI files

- GIVEN `MPRAGE_spm.nii` is identical and `MPRAGE_spm_normalized.nii` differs
- THEN the report MUST flag the first IDENTICAL and the second DIVERGENT with max absolute pixel difference

#### Scenario: Expected difference suppressed from new divergence

- GIVEN `Pseudo_CT_AC_Version.txt` differs but is in the known-expectations list
- THEN the report MUST flag it EXPECTED_DIFF, not DIVERGENT

#### Scenario: File present in one tree only

- GIVEN `Fusion_MR_Pseudo_CT_validation.tiff` exists only locally
- THEN the report MUST flag it LOCAL_ONLY

### Requirement: Comparison Semantics

| File type | Method | Tolerance |
|-----------|--------|-----------|
| `.nii` | `spm_read_vols` pixel diff | 1e-6 (configurable) |
| `.dcm` | Header + pixel diff | 1e-6 for pixel data |
| `.mat`, text | MD5 byte-level | Exact match |

#### Scenario: Tolerance absorbs float rounding

- GIVEN two NIfTI volumes with max abs diff < 1e-6
- THEN the report MUST report IDENTICAL

#### Scenario: Byte-level mismatch detected

- GIVEN two `.mat` SPM batch files with different parameter values
- THEN the report MUST report DIVERGENT with MD5 mismatch

## Non-Goals

- Does NOT fix root cause of divergence.
- Does NOT modify or rebuild the compiled Launchpad v2.0 binary.
- Does NOT require CI to run full clinical datasets.
- `pseudo_CT_cleanup_intermediates` remains unchanged.
