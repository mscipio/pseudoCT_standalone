# matlab-version-e2e-compatibility Specification

## Purpose

Diagnostic harness comparing full pipeline output across five MATLAB versions against the fixed Launchpad reference at `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/test_data_launchpad`, producing a quantitative Markdown compatibility matrix.

## Requirements

### Requirement: MATLAB Version Discovery

The system SHALL discover runtimes from `/usr/pubsw/bin/matlab*` and SHALL accept only R2010b, R2013b, R2018b, R2022b, and R2026a for the sweep. Any other version SHALL be skipped with a logged reason. Unavailable versions SHALL produce an actionable skip cell, never a substitute executable.

#### Scenario: Valid version enlisted

- GIVEN `/usr/pubsw/bin/matlab7.11` exists and maps to R2010b
- WHEN the runner queries available MATLABs
- THEN R2010b SHALL appear in the sweep list

#### Scenario: Pre-R2010b version excluded

- GIVEN `/usr/pubsw/bin/matlab7.0` exists (pre-R2010b)
- WHEN the runner discovers it
- THEN it SHALL be skipped with a logged reason

### Requirement: Dual PCA-Mode Sweep

The system SHALL execute the pipeline twice per MATLAB version: once with `PSEUDOCT_USE_PRINCOMP=0` (native PCA) and once with `PSEUDOCT_USE_PRINCOMP=1` (legacy shim). Each run SHALL preserve `MR_PET/tmp/` via `PSEUDOCT_KEEP_TMP=1`.

#### Scenario: Both modes produce tagged output

- GIVEN R2026a is available
- WHEN the sweep executes
- THEN two output trees SHALL exist, tagged by PCA mode

#### Scenario: Missing MATLAB reported as skip

- GIVEN R2018b is not installed
- WHEN the runner attempts execution
- THEN the cell for R2018b SHALL show `SKIP: not installed`

### Requirement: Full-Artifact Comparison

The system SHALL compare every artifact in each local output tree against its Launchpad counterpart using `diff_entrypoint_runs.m`. Comparison SHALL cover `MR_PET/tmp/`, `MR_PET/`, and `MR/pseudo_muMAP/`. NIfTI voxel data SHALL use tolerance 1e-6.

#### Scenario: Byte-identical artifact

- GIVEN `mprage.nii` matches the reference byte-for-byte at tol 1e-6
- WHEN comparison runs
- THEN status SHALL be IDENTICAL

#### Scenario: Divergent optimizer output

- GIVEN `rwAtlas_bone_*.nii` differs by max voxel 0.12 vs reference
- WHEN comparison runs
- THEN status SHALL be VOXEL_DIVERGENT with the max absolute difference recorded

### Requirement: Quantitative Compatibility Report

The system SHALL emit `compatibility.md` containing two Markdown tables (one per PCA mode). Each table SHALL have pipeline-stage rows ordered by execution sequence and MATLAB-version columns. Every cell SHALL report: status, `compared/expected` count, maximum voxel/pixel difference, and mismatch count.

#### Scenario: Complete matrix rendered

- GIVEN all five versions ran with both PCA modes
- WHEN the report is generated
- THEN `compatibility.md` SHALL contain two tables × 15 stage rows × 5 version columns, all cells filled

### Requirement: Missing-Artifact and Uncomparable Status

The system SHALL explicitly report LOCAL_ONLY, LAUNCHPAD_ONLY, and UNCOMPARABLE status per artifact with reason. LOCAL_ONLY artifacts SHALL NOT be counted as coverage failures. UNCOMPARABLE SHALL include the reason (e.g., file type mismatch, corrupted reference).

#### Scenario: QC TIFF is local-only

- GIVEN `Fusion_MR_Pseudo_CT_validation.tiff` exists locally but not in the Launchpad reference
- WHEN comparison runs
- THEN status SHALL be LOCAL_ONLY and SHALL NOT cause a coverage failure

### Requirement: Semantic vs Metadata Separation

The system SHALL classify voxel/pixel-level divergence (VOXEL_DIVERGENT, DIVERGENT) separately from metadata-only differences (HEADER_ONLY_DIFF, EXPECTED_DIFF). Metadata noise SHALL include: NIfTI header `mat`/`pinfo`/`dt` fields, QFORM0 rounding warnings, version strings, and `spm_vol` header drift.

#### Scenario: Version text is expected diff

- GIVEN `Pseudo_CT_AC_Version.txt` differs between local and Launchpad
- WHEN comparison runs
- THEN status SHALL be EXPECTED_DIFF, not VOXEL_DIVERGENT or DIVERGENT

### Requirement: No Source Modification

The compatibility harness SHALL NOT modify any existing pipeline source, default, comparator, CI workflow, changelog, or release-cleanup file. All deliverables SHALL be additive under `scripts/` and `docs/`.

#### Scenario: Filesystem audit passes

- GIVEN the harness is deployed
- WHEN `git diff --name-only` is run against the base branch
- THEN no modified file SHALL appear under `src/`, `vers/`, `CHANGELOG.md`, `.github/`, or `Batch_atlas/`
