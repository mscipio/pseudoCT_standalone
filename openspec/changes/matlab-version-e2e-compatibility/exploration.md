# Exploration: MATLAB-Version E2E Compatibility

**Change name:** `matlab-version-e2e-compatibility`
**Engram topic_key:** `sdd/matlab-version-e2e-compatibility/explore`
**Project:** `pseudoct_standalone`
**Date:** 2026-07-13
**Status:** Explore — no code changes proposed; manual E2E test design only
**Mode:** Hybrid (OpenSpec + Engram), interactive, single-PR default, 800-line review budget
**Constraint:** Exploration only. Do NOT edit any source code or existing files. The only new file
this phase may produce is this `exploration.md` (and its Engram twin).

---

## TL;DR

1. The investigation has already isolated the late-stage divergence to `spm_run_coreg_estimate`'s
   optimizer trajectories on the same byte-identical input — MATLAB 7.11 matches the compiled
   Launchpad v2.0 / MCR 7.11 exactly; R2026a diverges by max affine element 0.122425
   (Engram #267, [[pseudo_ct_matlab_runtime_compatibility]]). That evidence is already durable
   in the repo. The proposed `matlab-version-e2e-compatibility` change is **not** about
   re-discovering that; it is about designing a **repeatable manual E2E test** that
   walks the full pipeline stage by stage across incremental MATLAB versions and
   reports the **first** stage with deterministic numerical divergence.
2. The test fixture already exists on disk: `test_data_local/MR/MPRAGE/*.dcm` (208 DICOMs),
   `test_data_local/MR/UMAP/*.dcm` (128), and `test_data_launchpad/MR_PET/tmp/` (the Launchpad
   reference run we compare against). The pipeline is fully observable via
   `PSEUDOCT_KEEP_TMP=1` (already implemented) and the existing `diff_entrypoint_runs.m`
   comparator (already implemented and smoke-tested at 90+ pass). The new test is therefore
   a **sequencing + report-format problem**, not a new-tooling problem.
3. The E2E plan must distinguish three classes of difference: (a) **deterministic
   semantic** — voxel data shifts under SPM/MATLAB optimizers; (b) **byte-level / metadata**
   — pseudo_CT_AC_Version.txt, Fusion MR/Pseudo-CT TIFF, `MR_PET/tmp/mu512/` scratch dir,
   `QFORM0` rounding warnings from `spm_preproc_write8`; (c) **environmental** — FreeSurfer
   5.3 child `libstdc++.so.6` failure on MCR 7.11, `pca` vs `princomp` output, `vers/`
   override vs SPM-tree default. A robust report format must show the first
   DIVERGENT (or VOXEL_DIVERGENT) stage in the pipeline sequence, with a separate row
   for the runtime's housekeeping noise.
4. **Critical overlap with the in-flight `investigation-cleanup-release`** (apply phase,
   tasks 4.4 still open): that change owns the comparator, the keep-tmp plumbing, the
   release-packaging and changelog. This new change MUST NOT touch any of those
   files, MUST NOT add new test scripts under `scripts/` (it would block their
   smoke-test additions), and MUST NOT introduce a new entry in `CHANGELOG.md`
   while that change is in flight. The deliverable here is a **procedure document**
   plus a **report template**, not code.
5. The recommended minimal reproducible dataset is the **existing**
   `test_data_local/MR/MPRAGE/<single DICOM>` + auto-discovered UMAP. No new
   fixtures required. The recommended report format is a single `compatibility.csv`
   + a per-stage `first_divergence.json` for the operator to read. The recommended
   runner is a thin shell helper that calls `run_pseudo_CT_local` per MATLAB
   install under `/autofs/cluster/matlab/`, gating keep-tmp and capturing env, and
   is the only **new** artifact this change introduces — and even that is optional
   (the operator can run the steps manually).

---

## Current State

### Pipeline stages and observable checkpoints

Read directly from `src/core/atlas_based_attenuation_map.m` (676 lines) and
`src/io/pseudo_CT_write_mu_map_dicom.m`. The full sequence is:

| # | Stage | File / call | Checkpoint artifact (in `MR_PET/tmp/`) |
|---|-------|-------------|------------------------------------------|
| 1 | DICOM → NIfTI | `convert_dicom_i_2_nii.m` (called from `run_pseudo_CT_local.m:207`) | `mprage.nii` |
| 2 | FreeSurfer `mri_normalize` | `run_normalization_cmd.m` (local) or cluster (Launchpad) | `mprage_normalized.nii` |
| 3 | Subject recentering | `center_subject_in_image.m` (gated by `recenter_before_normalization` default) | rewrites `mprage_normalized.nii` |
| 4 | Reorient toward MNI template | `move_image_2_MNI.m` (PCA-based affine to `ch2.nii`) | `mmprage.nii` |
| 5 | `_repos` suffix renaming | `move_image_2_MNI.m` (line 270-275) | `mprage_normalized_repos.nii` |
| 6 | Smoothing + subject-mask | `spm_smooth(FWHM=4)` + `head_mask_mprage` | `smprage_normalized_repos.nii` (NaN outside mask) |
| 7 | New Segment | `cfg_util('run', new_segment_batch.mat)` | `c1..c6mprage_normalized_repos.nii`, `mwc1..6`, `mprage_normalized_repos_seg8.mat` |
| 8 | `reduce_bone_segment` | `reduce_bone_segment.m` | `rc1..rc6mprage_normalized_repos.nii` |
| 9 | DARTEL existing-template | `cfg_util('run', dartel_existing_template_batch.mat)` | `u_rc1mprage_normalized_repos.nii` (flow field) |
| 10 | Inverse warp (atlases → subject) | `cfg_util('run', create_inverse_warped_batch.mat)` | `wAtlas_*_u_rc1*.nii` |
| 11 | Final reslice | `spm_reslice(Pr, flg)` | `rwAtlas_*_u_rc1*.nii` |
| 12 | CT → att_map | `CT_2_att_map.m` + mask multiply | `att_map_no_filled.nii`, `att_map.nii` |
| 13 | DICOM mu-map write | `pseudo_CT_write_mu_map_dicom.m` | `MR/pseudo_muMAP/*.dcm` |
| 14 | QC TIFF | `quick_fusion_pseudo_ct` | `MR_PET/Fusion_MR_Pseudo_CT_validation.tiff` (local only) |
| 15 | Version log | `pseudo_CT_write_version_log` | `MR_PET/Pseudo_CT_AC_Version.txt` (local: from CHANGELOG; Launchpad: hardcoded v2.0) |

The **divergent region identified by prior work** ([pseudo_ct_entrypoint_divergence_diagnosis],
Engram #267) is **stages 7-10** (New Segment + DARTEL + inverse warp), specifically inside
`spm_run_coreg_estimate`'s optimizer trajectories. Stage 4 (`move_image_2_MNI`) is the
**pre-coreg geometry** that the PCA shim (`pseudo_ct_princomp_legacy.m`) restores to legacy
parity on R2013b+ MATLABs.

### Existing tooling (already shipped, reuse only)

| Tool | Path | Role for this change |
|------|------|----------------------|
| `PSEUDOCT_KEEP_TMP=1` | env var | Preserves `MR_PET/tmp/` end-to-end; required for stage-by-stage comparison |
| `diff_entrypoint_runs.m` | `scripts/diff_entrypoint_runs.m` (566 lines, smoke-tested 4/4 dispatch) | Compares two `MR_PET/tmp/` trees; reports IDENTICAL / HEADER_ONLY_DIFF / VOXEL_DIVERGENT / DIVERGENT per file |
| `compare_nifti_data.m` | `scripts/compare_nifti_data.m` (131 lines) | File-I/O-free NIfTI comparison core (for synthetic tests) |
| `compare_hash_strings.m` | `scripts/compare_hash_strings.m` (51 lines) | MD5 with sentinel guard |
| `restart_from_repos_checkpoint.m` | `scripts/restart_from_repos_checkpoint.m` (485 lines) | Staged restart from `mprage_normalized_repos.nii`; can re-run stages 6+ on any MATLAB |
| `normalized_2_att_map.m` | `src/core/normalized_2_att_map.m` (474 lines) | Runs stages 6+ from a normalized checkpoint; supports `reuse_masked_checkpoint` and `use_compiled_spm8` |
| `sweep_smoothing_fwhm.m` | `scripts/sweep_smoothing_fwhm.m` (96 lines) | Sweeps `spm_smooth` FWHM 0-4 against reference; useful for stage 6 isolation |
| `pseudo_ct_princomp_legacy.m` | `src/core/pseudo_ct_princomp_legacy.m` (88 lines) | Legacy PCA; selected via `PSEUDOCT_USE_PRINCOMP=1` |
| `PSEUDOCT_DEBUG_MOVE2MNI=1` | env var | Writes `*_move2mni_debug.mat` with PCA theta, translation, affine matrices |
| `run_pseudo_CT_local.m` | repo root | Local pipeline entry (accepts cell array of DICOM paths) |
| `run_pseudo_CT_launchpad.m` | repo root | Launchpad entry — **opaque v2.0 binary**, useful as the reference only |

### Existing fixtures and references

| Path | Role |
|------|------|
| `test_data_local/MR/MPRAGE/*.dcm` (208 files) | Real subject MPRAGE, byte-identical to Launchpad fixture |
| `test_data_local/MR/UMAP/*.dcm` (128 files) | UMAP, auto-discovered by `pseudo_CT_auto_discover_ute_umap` |
| `test_data_local/MR_PET/MPRAGE_spm.nii` | Stage-1 reference; byte-identical to Launchpad (verified) |
| `test_data_local/MR_PET/MPRAGE_spm_normalized.nii` | Stage-2 reference; **diverges** from Launchpad (known) |
| `test_data_local/MR_PET/tmp/` (preserved as of 2026-07-10) | Full reference run; 35+ files including all stage outputs |
| `test_data_launchpad/MR_PET/tmp/` (preserved) | Launchpad reference run on same subject |
| `coreg_input_canonical.nii`, `coreg_input_711.nii`, `coreg_input_2026a.nii` | Controlled coreg inputs (outside repo, under `pseudoCT_devel/`) |
| `coreg_result_711.mat`, `coreg_result_2026a.mat` | The two coreg results that prove runtime drift |
| `dist/Batch_atlas/` | The 7 DARTEL templates + atlases + batch `.mat` files |
| `/autofs/cluster/matlab/` | 30+ MATLAB installs (5.0 through R2026a) available for the sweep |

### OpenSpec state (potential conflict surface)

| Change | Status | Conflict risk |
|--------|--------|---------------|
| `entrypoint-divergence-diagnosis` | All 5 phases complete; 3 manual E2E tasks (4.3, 4.4, 4.5) unchecked; staged in `git status` | **Low** — this change depends on its tooling but does not modify it |
| `investigation-cleanup-release` | Apply phase in progress; 4.4 still open; 25 files staged + 21 modified | **HIGH** — this change shares `CHANGELOG.md`, the comparator, the `src/core/` diagnostic helpers, the `openspec/` folder. Any new artifact added by us will conflict with the in-flight cleanup |
| `local-pipeline-end-compat` | Open change folder; no verify-report; uncommitted source edits | **Medium** — overlaps with the source-edit layer (this change is documentation-only, so the risk is "do not commit your file into the same PR" rather than "do not modify the same lines") |
| `extract-version-changelog` | Archived 2026-07-07 | None |
| `launchpad-matlab-compat` | Archived 2026-06-26 | None — superseded by Engram #267; this new change re-uses its findings |

### AGENTS.md and CHANGELOG.md constraints

`CHANGELOG.md` is currently at v2.6.2 (line 1: `2.6.2`) with the Investigation Cleanup Release
entry. The in-flight `investigation-cleanup-release` change owns the next entry. **This
change MUST NOT add a v2.6.3 or v2.7.0 entry** — that belongs to whoever tags the
next release, which is downstream of the cleanup. If the user wants this E2E test
documented in the changelog, it should be deferred to the next release cycle
or, more cleanly, live in a dedicated `docs/` artifact (e.g.
`docs/matlab-version-compat-E2E.md`) referenced from the wiki, not the changelog.

---

## Affected Areas (evidence-based; no implementation changes proposed)

This change is intentionally **non-code** for the apply phase. The affected areas are
limited to **investigation documentation** under `openspec/` and **engram topic keys**.

| Area | Type | Why |
|------|------|-----|
| `openspec/changes/matlab-version-e2e-compatibility/exploration.md` (this file) | New | Phase-1 deliverable |
| `openspec/changes/matlab-version-e2e-compatibility/` (future phase files) | New folder | Reserved for `proposal.md`, `specs/`, `design.md`, `tasks.md`, `verify-report.md` |
| Engram topic `sdd/matlab-version-e2e-compatibility/explore` | New | Twin of this artifact |
| Engram topic `sdd/matlab-version-e2e-compatibility/compatibility-matrix` (future) | Reserved | Will hold the operator's compatibility table after E2E run |
| `docs/matlab-version-compat-E2E.md` (future, optional) | New | Operator-facing procedure + report format |
| `scripts/run_matlab_version_e2e.sh` (future, optional) | New | Thin shell wrapper to run `run_pseudo_CT_local` per MATLAB install under `/autofs/cluster/matlab/`. Optional: the operator can run the steps manually |
| `scripts/run_matlab_version_e2e_report.m` (future, optional) | New | Aggregates per-version `MR_PET/tmp/` trees into `compatibility.csv` and `first_divergence.json` |

**Not affected (explicit non-targets):**

- Any file under `src/`, `vers/`, `spm8-r6313/`, `imgaussian/`, `ssh2_v2_m1_r5/`, `Batch_atlas/`
- `CHANGELOG.md` (owned by `investigation-cleanup-release`)
- `AGENTS.md` (no behavior change to document)
- `defaults_pseudo_CT.m`, `defaults_pseudo_CT_launchpad.m` (no new defaults)
- The `PSEUDOCT_*` env-var set (no new env vars; we reuse the existing five)
- The `dist/pseudoCT_v2.6.1/` package (no rebuild)
- Any `scripts/compare_*.m` or `scripts/diff_entrypoint_runs.m` (we consume them, do not modify them)
- `scripts/run_smoke_tests.m` (would conflict with the in-flight 1038-line diff)

---

## Approaches

### 1. Pure manual procedure document (no new scripts)

- **Description:** Produce a single `docs/matlab-version-compat-E2E.md` with step-by-step
  instructions for an operator to run `run_pseudo_CT_local` per MATLAB install, capture
  `MR_PET/tmp/` per version, then call `diff_entrypoint_runs.m` pairwise against the
  Launchpad reference. No new code, no new scripts, no OpenSpec specs.
- **Pros:** Zero conflict with `investigation-cleanup-release`. Review budget trivially safe.
  Operator can start running today.
- **Cons:** No automation; every comparison must be re-typed. The "first divergence"
  identification relies on the operator reading the comparator's console table by eye.
  No persistent report format — the operator must take screenshots or hand-build the CSV.
- **Effort:** Low. ~80 lines of markdown.

### 2. Recommended: procedure + thin shell runner + thin report aggregator (no source edits)

- **Description:** Add three files outside the implementation surface:
  1. `docs/matlab-version-compat-E2E.md` — the procedure and report-format spec.
  2. `scripts/run_matlab_version_e2e.sh` — POSIX shell wrapper that:
     - iterates over a list of MATLAB versions (default: every install under
       `/autofs/cluster/matlab/` that is R2010b or later),
     - sets `PSEUDOCT_KEEP_TMP=1`, `PSEUDOCT_USE_PRINCOMP=0` (default) or `=1` (legacy),
     - sources `setup_pseudo_CT_paths.m` via `matlab -batch`,
     - calls `run_pseudo_CT_local({...DICOM-path...})` on a single subject,
     - copies the resulting `MR_PET/tmp/` to a version-tagged scratch dir
       (e.g. `e2e_run_<timestamp>/matlab_R2026a/MR_PET/tmp/`).
  3. `scripts/run_matlab_version_e2e_report.m` — MATLAB aggregator that:
     - walks a root directory of per-version trees,
     - runs `diff_entrypoint_runs` pairwise against the Launchpad reference,
     - writes `compatibility.csv` (rows = stages, cols = MATLAB version, cells = status),
     - writes `first_divergence.json` (the first DIVERGENT/VOXEL_DIVERGENT file per version,
       plus the first IDENTICAL/HEADER_ONLY_DIFF preserved stage, plus env metadata).
- **Pros:**
  - Operator can re-run any time on any subject.
  - The `compatibility.csv` is the durable artifact the user asked for ("produces a
    compatibility table pinpointing the first pipeline stage with divergent numerical results").
  - The shell wrapper is the only new line of code that touches the env (via
    `PSEUDOCT_KEEP_TMP`); it does NOT edit any existing MATLAB source.
  - The aggregator reuses `diff_entrypoint_runs.m` (already shipped); no comparator work.
  - Review budget: ~250 lines total (procedure 80 + shell 50 + report 120). Well under 800.
- **Cons:**
  - Three new files in `docs/` and `scripts/`. Will conflict with the in-flight
    `investigation-cleanup-release` only at the `scripts/` folder; mitigation below.
  - The shell wrapper assumes the operator has `matlab` on PATH for each version
    (or sets the right `LD_LIBRARY_PATH`); see Risks.
- **Effort:** Low-medium. ~250 lines total, all under `docs/` and `scripts/`.

### 3. Heavy: full MATLAB-version matrix CI job

- **Description:** Wire the above into `.github/workflows/ci.yml` as a matrix job spanning
  MATLAB R2010b, R2013b, R2018b, R2022b, R2026a. Each job runs the same subject, captures
  the comparator output, publishes a matrix artifact.
- **Pros:** Fully automated reproducibility.
- **Cons:**
  - GitHub Actions has no MATLAB 7.11 / MCR 7.11 available; the licensing problem from
    `pseudo_ct_attenuation_correction` wiki page (CI Licensing Issue) already blocks this.
  - Adding a matrix job would require a self-hosted runner with all MATLAB versions
    installed. The user does not have that today.
  - The CI workflow is owned by the next release cycle, not by this change.
- **Effort:** High. Out of scope.

### 4. Hybrid: piggyback on `entrypoint-divergence-diagnosis` tasks 4.3-4.5

- **Description:** The three unchecked manual E2E tasks in `entrypoint-divergence-diagnosis`
  (4.3, 4.4, 4.5) are exactly what the user is now asking for, generalized to a MATLAB-version
  matrix. We extend those tasks instead of starting a new change.
- **Pros:** No new OpenSpec folder; reuses an existing in-flight verify report.
- **Cons:**
  - `entrypoint-divergence-diagnosis` is already a closed-changes-equivalent (staged in
    `git status`, verify-report written, tasks 1-3 + 5-6 all checked). The 3 unchecked
    tasks are operator-side manual runs, not design changes. Extending them would
    retroactively re-open a closed change.
  - The user explicitly asked for a new change name (`matlab-version-e2e-compatibility`).
  - The two changes have different intents: 4.3-4.5 confirm the keep-tmp flag works on
    one pair of entrypoints; this new change sweeps a version matrix.
- **Effort:** High organizational overhead. Not recommended.

---

## Recommendation

**Approach 2** — produce a procedure document, a thin POSIX shell runner, and a thin
MATLAB report aggregator. All artifacts under `docs/` and `scripts/`. No source edits.
No CHANGELOG entry. No env-var additions. No changes to the comparator, the
defaults, the entry scripts, or the in-flight `investigation-cleanup-release` work.

### Concrete plan for the next phases

The change becomes a three-artifact change with two sub-tasks:

- **Task A — Procedure document** (`docs/matlab-version-compat-E2E.md`, ~80 lines)
  - States the goal, the existing tooling it reuses, the dataset, the env-var matrix,
    the per-version invocation, and the per-version output layout.
  - Specifies the report format (CSV columns, JSON schema).
  - Lists the version matrix to run (R2010b, R2013b, R2018b, R2022b, R2026a; the
    union of "all installs in `/autofs/cluster/matlab/` ≥ R2010b"; the wiki page
    [[pseudo_ct_matlab_runtime_compatibility]] already names R2010b as the bit-exact
    reference and R2026a as the divergent one).
  - Documents the three difference classes and how to read them.

- **Task B — POSIX shell runner** (`scripts/run_matlab_version_e2e.sh`, ~50 lines)
  - Usage: `MATLAB_VERSIONS="R2010b R2026a" SUBJECT_DICOM=.../0001.dcm
    OUT_ROOT=/tmp/e2e_$(date +%s) ./scripts/run_matlab_version_e2e.sh`.
  - Per version: detect `/autofs/cluster/matlab/<version>/bin/matlab` (or
    `matlab -batch "version"` via the system wrapper if installed),
    set `PSEUDOCT_KEEP_TMP=1`, `PSEUDOCT_USE_PRINCOMP=0` (default) or `=1` (legacy run),
    call `matlab -batch "run_pseudo_CT_local({'<DICOM>'})"`,
    copy `MR_PET/tmp/` to `<OUT_ROOT>/matlab_<version>/MR_PET/tmp/`.
  - Prints a per-version summary line at the end. No global state; idempotent re-runs.

- **Task C — MATLAB report aggregator** (`scripts/run_matlab_version_e2e_report.m`, ~120 lines)
  - Usage: `run_matlab_version_e2e_report('/path/to/e2e_root', '/path/to/launchpad_ref_tmp')`.
  - Walks `e2e_root/matlab_*/MR_PET/tmp/`, calls `diff_entrypoint_runs(local_tmp, launchpad_ref_tmp, 'OutputCSV', '<...>')`
    for each, then post-processes the per-version CSVs into:
    - `compatibility.csv` — rows = pipeline stages (mprage.nii, mprage_normalized.nii,
      mprage_normalized_repos.nii, smprage_normalized_repos.nii, c1..6, mwc1..6, rc1..6,
      u_rc1, w*Atlas_*, rw*Atlas_*, att_map.nii), cols = MATLAB version, cells =
      IDENTICAL / HEADER_ONLY_DIFF / VOXEL_DIVERGENT / DIVERGENT / LOCAL_ONLY / LAUNCHPAD_ONLY.
    - `first_divergence.json` — `{ "<version>": { "first_divergent_file": "...",
      "max_abs_diff": 0.122425, "first_identical_after_divergence": "...",
      "matlab_version": "...", "psuedoct_use_princomp": 0, "psuedoct_keep_tmp": 1,
      "subject": "..." } }`.
  - The aggregator imports the existing `diff_entrypoint_runs` (no copy, no edit).

### Comparison strategy — how to distinguish semantic from binary

For each per-version `MR_PET/tmp/`, the aggregator must:

1. **NIfTI files** — use the existing `compare_nifti_data` (called via `diff_entrypoint_runs`).
   - **VOXEL_DIVERGENT** (max abs diff > 1e-6) = **deterministic semantic**.
   - **HEADER_ONLY_DIFF** (header `mat`/`pinfo`/`dt` differs, voxels identical at tol) = **binary/metadata**.
   - **IDENTICAL** (within 1e-6) = **passes this stage** under this runtime.
2. **`.mat` SPM batch files** — `new_segment_<date>_batch.mat`,
   `dartel_existing_template_<date>_batch.mat`, `create_inverse_warped_<date>_batch.mat` —
   MD5 byte-level. The dates will differ between runs (cosmetic); strip the date
   substring before MD5 to avoid false DIVERGENT. Or just whitelist these as
   `KNOWN_LOCAL_ONLY` extensions of the comparator's known-expected list — the
   aggregator's job is to report, not to redefine the comparator.
3. **`.txt`** — `Pseudo_CT_AC_Version.txt` is EXPECTED_DIFF (already in the comparator's
   known-expected list). If the aggregator sees it, it filters it.
4. **`.tiff`** — `Fusion_MR_Pseudo_CT_validation.tiff` is LOCAL_ONLY (Launchpad does not
   produce it; the aggregator reports it but does not count it as a divergence).
5. **Subdirs** — `MR_PET/tmp/mu512/` exists in some runs (a scratch dir; ignore as
   `LOCAL_ONLY`).

The "first divergence" is the earliest stage (by pipeline order, NOT alphabetical) whose
status is `VOXEL_DIVERGENT` or `DIVERGENT`. Stages 1-2 are byte-stable in
existing data; stages 7-10 are the expected divergence region; stages 13-15 are
expected-binary (DICOM, version text, QC TIFF).

### Why this approach

- The user asked for a **repeatable manual E2E test**, not a fix. The change
  delivers exactly that and nothing more.
- The shell wrapper is the only "code" and it is **optional** — the operator can
  run the steps manually if they prefer. That keeps the change reviewable as
  documentation with a thin automation tail.
- The aggregator reuses `diff_entrypoint_runs.m` (already smoke-tested). No comparator
  work, no smoke-test changes, no `scripts/run_smoke_tests.m` conflict.
- The report format is a CSV + a JSON. Both are durable, diffable, and paste-able
  into the wiki or a paper.
- The user explicitly said "Another agent is currently cleaning the repository for a
  release, so avoid touching implementation files and report potential overlap/conflicts."
  This approach touches zero implementation files and the only script overlap is
  additive (one new `.sh` and one new `.m`, both in folders where the cleanup
  is not editing).

---

## Risks

| Risk | Likelihood | Evidence / mitigation |
|------|------------|----------------------|
| **Conflict with in-flight `investigation-cleanup-release`** (25 files staged, 21 modified, 4.4 open) | High if we add files under `src/`, `vers/`, `CHANGELOG.md`, `openspec/specs/` | Mitigation: this change adds zero files under those paths. The new shell script and report `.m` go in `scripts/`; the procedure doc goes in a new `docs/` folder. The in-flight cleanup is not editing `scripts/run_matlab_version_e2e.*` or `docs/`. The OpenSpec folder `openspec/changes/matlab-version-e2e-compatibility/` is independent of `investigation-cleanup-release/`. **Action: confirm with the other agent that the new `docs/` folder is acceptable, and that the new `scripts/run_matlab_version_e2e.sh` and `run_matlab_version_e2e_report.m` will not be re-tracked by the cleanup's smoke-test additions.** |
| **R2026a child `libstdc++.so.6` failure** (FreeSurfer 5.3) | High | Already solved by `PSEUDOCT_FS_LIBSTDCPP_ROOT` (default `/autofs/cluster/matlab/current/sys/os/glnxa64`). The shell wrapper must export this env var before invoking `matlab -batch`. Documented in [[pseudo_ct_matlab_runtime_compatibility]] and the entry script. |
| **MCR 7.11 vs MCR 9.x SPM8 `QFORM0` rounding warnings** | High | `spm_preproc_write8.m` (in `vers/`) emits `QFORM0 representation has been rounded` warnings. These are byte-level metadata noise, not voxel divergence. The aggregator's status filter ignores warnings. |
| **MATLAB 7.11 missing functions on R2010b** (`strsplit`, `isstr` operator, etc.) | High on R2010b | Already fixed by `launchpad-matlab-compat` (archived 2026-06-26) and `local-pipeline-end-compat` (open, uncommitted). For the E2E test, the R2010b run is the **reference**, not the variable; divergence reporting is from R2013b+ outward. Document in the procedure. |
| **PCA shim path selection** — `PSEUDOCT_USE_PRINCOMP=0` (modern) vs `=1` (legacy) | Medium | The shim restores pre-coreg geometry on R2013b+. The procedure must run TWO sweeps: one with `PSEUDOCT_USE_PRINCOMP=0` (default), one with `=1`. The compatibility table will then show whether the shim closes the pre-coreg gap (expected) and whether the runtime drift still appears at the optimizer (expected). |
| **DICOM mu-map re-encoding is lossy** | High (Stage 13) | Already known. The comparator's NIfTI tolerance absorbs float rounding; the DICOM comparator compares 12 key header fields and pixels with tol. The aggregator treats DICOM stages as INFORMATIONAL, not semantic. |
| **The 30+ MATLAB installs include pre-R2010b versions** (5.0, 5.3, 6.0, 6.1, 6.5, 6.5.1, 7.0, 7.0.1, 7.0.4, 7.1, 7.2, 7.3, 7.4, 7.5, 7.7, 7.8, 7.9) | High — pre-R2010b may not have required SPM8 functions | The procedure MUST default the version list to `R2010b R2013b R2018b R2022b R2026a`. Pre-R2010b installs are out of scope. The shell wrapper should warn if asked to include them. |
| **The shell wrapper invokes `matlab -batch` which needs a display** | Low | `-batch` runs without a display on every modern MATLAB; the existing entry scripts already use this pattern in `scripts/run_lint.m` and `scripts/run_smoke_tests.m` (which run under `matlab -nodesktop -nosplash -nodisplay -r`). The shell wrapper uses the same pattern. |
| **Per-MATLAB `LD_LIBRARY_PATH` pollution from prior runs** | Medium | The wrapper exports `PSEUDOCT_FS_LIBSTDCPP_ROOT` per version; the entry script's own warning restore (`warning(orig_warn)`) prevents state leak. Document a "restart MATLAB or `unset LD_LIBRARY_PATH` between runs" note in the procedure. |
| **The aggregator's `first_divergence.json` schema is a contract** — if we change it later, downstream consumers break | Low | We pin the schema in the procedure doc, with v1 explicitly. Future changes require an additive new key, not a breaking rename. |
| **Reviewer expects a "fix" rather than a "test"** | Medium | The wiki page [[pseudo_ct_matlab_runtime_compatibility]] already documents that the runtime drift cannot be fixed from this repo. The proposal must lead with the same wording; the change is durable test infrastructure, not a fix. |
| **800-line budget is consumed by smoke-test expansion in cleanup** (the 1038-line exception) | Low | Our ~250 lines are independent. Total PR is well under 800. Single-PR default is safe. |

---

## Overlap / Conflict Report (explicit, per user request)

The user said: "Another agent is currently cleaning the repository for a release, so
avoid touching implementation files and report potential overlap/conflicts."

**Current in-flight state (read from `git status` and OpenSpec):**

1. `openspec/changes/investigation-cleanup-release/` is in **apply** phase, with 25 files
   staged and 21 files modified. Its tasks.md has task 4.4 still unchecked ("Operator
   confirms R2026a E2E validation deferral before release tagging"). Its current
   `apply-progress.md` is being written by the other agent.
2. `openspec/changes/local-pipeline-end-compat/` is open with a partial `tasks.md` (no
   verify-report). Source edits to `nii2dcm_header_copy_vb20_david.m` and
   `pseudo_CT_write_mu_map_dicom.m` are uncommitted.
3. `openspec/changes/extract-version-changelog/archive-report.md` was deleted in
   `investigation-cleanup-release` phase 1.2; that change owns the cleanup.
4. `CHANGELOG.md` is at v2.6.2 (cleanup release entry). The next changelog entry
   (v2.6.3 or v2.7.0) is owned by whoever tags the next release. **This change
   does not own that.**

**Overlap with this change (by area):**

| Area | Owned by | This change's plan | Conflict? |
|------|----------|--------------------|-----------|
| `CHANGELOG.md` | `investigation-cleanup-release` | Do NOT edit | **No** |
| `src/`, `vers/`, `spm8-r6313/`, `imgaussian/`, `ssh2_v2_m1_r5/`, `Batch_atlas/` | n/a (not in flight) | Do NOT edit | **No** |
| `src/core/atlas_based_attenuation_map.m` (line 90-104 CHANGELOG version read) | `extract-version-changelog` (archived) | Do NOT edit | **No** |
| `src/core/move_image_2_MNI.m` (PCA shim, `PSEUDOCT_DEBUG_MOVE2MNI`) | `investigation-cleanup-release` (staged) | Do NOT edit | **No** |
| `src/config/defaults_pseudo_CT.m` (`recenter_before_normalization`, `keep_temp_files`) | `investigation-cleanup-release` (staged) | Do NOT edit; reuse via env | **No** |
| `src/config/setup_pseudo_CT_paths.m` | `investigation-cleanup-release` (staged) | Do NOT edit; the shell wrapper calls `run_pseudo_CT_local` which calls this | **No** |
| `scripts/diff_entrypoint_runs.m` | `investigation-cleanup-release` (staged) | Consume only, do not edit | **No** |
| `scripts/compare_nifti_data.m` | `investigation-cleanup-release` (staged) | Consume only via `diff_entrypoint_runs` | **No** |
| `scripts/compare_hash_strings.m` | `investigation-cleanup-release` (staged) | Consume only via `diff_entrypoint_runs` | **No** |
| `scripts/restart_from_repos_checkpoint.m` | `investigation-cleanup-release` (staged) | Consume only — could be used as an alternative to `run_pseudo_CT_local` for stages 6+ | **No** |
| `scripts/sweep_smoothing_fwhm.m` | `investigation-cleanup-release` (staged) | Reference only; could be reused for FWHM sensitivity | **No** |
| `scripts/run_smoke_tests.m` (1038-line expansion) | `investigation-cleanup-release` (staged) | Do NOT add new smoke tests to this file (would conflict with their staged diff) | **No (deliberately)** |
| `scripts/run_lint.m` | n/a | Do NOT add new files to its glob | **No** |
| `scripts/run_tests.m` (operator cookbook) | `investigation-cleanup-release` (marked Remove) | We do not depend on it; we write our own `run_matlab_version_e2e.sh` | **No** |
| `openspec/specs/entrypoint-divergence-diagnostics/spec.md` | `investigation-cleanup-release` (staged) | We do not modify the spec; we consume its `KNOWN_EXPECTED_DIFF` and `KNOWN_LOCAL_ONLY` lists via the comparator | **No** |
| `openspec/specs/launchpad-matlab-compat/spec.md` | archived | n/a | **No** |
| `openspec/specs/release-packaging/spec.md` | `investigation-cleanup-release` (staged) | n/a — we do not own packaging | **No** |
| `openspec/changes/extract-version-changelog/archive-report.md` | already deleted by cleanup | n/a | **No** |
| `package-lock.json` | already deleted by cleanup | n/a | **No** |
| `spm8-dan/` (1.1 GB) | already gitignored by cleanup | n/a | **No** |
| `docs/` | new | We CREATE this folder | **Possible** — confirm with the other agent that `docs/` is acceptable. If not, fall back to `openspec/changes/matlab-version-e2e-compatibility/PROCEDURE.md`. |
| `scripts/run_matlab_version_e2e.sh` | new | We CREATE this file | **No** — neither the cleanup nor the local-pipeline-end-compat change is adding this filename. If the cleanup's smoke-test expansion adds a glob for `scripts/*.m`, the new `.sh` is unaffected (it is not `.m`). |
| `scripts/run_matlab_version_e2e_report.m` | new | We CREATE this file | **Possible** — the cleanup's smoke-test additions parse every `scripts/*.m`; the new `.m` will be added to the parse list when `run_smoke_tests.m` is re-run. Confirm parse passes. |
| `openspec/changes/matlab-version-e2e-compatibility/` | new folder | We CREATE this folder | **No** — independent OpenSpec change folder. |

**Net overlap:** Zero implementation files. Three new artifacts (one `docs/`, one
`scripts/.sh`, one `scripts/.m`). One **soft conflict** with the in-flight cleanup
on the new `scripts/*.m` file (it will be auto-included in the next `run_smoke_tests.m`
parse sweep) and one **optional-conflict** on the new `docs/` folder (proposed but
not yet present in the repo).

**Recommended coordination:** Before opening the PR, ask the other agent to confirm
(a) the `docs/` folder is acceptable, (b) the new `scripts/run_matlab_version_e2e_report.m`
will pass their parse-check glob, (c) the new OpenSpec folder will not collide with
their `sdd-archive` of `investigation-cleanup-release`. If any of those are NO, this
change folds its artifacts into `openspec/changes/matlab-version-e2e-compatibility/`
rather than `docs/` and `scripts/`.

---

## Open Questions for the Proposal Phase

1. **Shell wrapper vs pure manual** — do you want the optional shell wrapper, or is a
   procedure document enough? (Recommendation: include the wrapper; it is ~50 lines and
   makes the test reproducible by a different operator.)
2. **Version matrix default** — the procedure defaults to R2010b, R2013b, R2018b, R2022b,
   R2026a. Should the default also include R2011b, R2012a/b, R2014a/b, R2015a/b, R2016a,
   R2017a/b, R2019a/b, R2020a/b, R2021a/b, R2023a/b, R2024a/b, R2025a/b? Trade-off: more
   rows in the compatibility table, longer runtime. (Recommendation: start with the 5
   named versions; expand only if the first sweep is inconclusive.)
3. **PSEUDOCT_USE_PRINCOMP** — run with both `=0` (modern PCA, default) and `=1` (legacy
   shim)? This doubles the matrix. (Recommendation: yes — it answers the "does the shim
   close the gap" question explicitly.)
4. **DICOM stage reporting** — treat stages 13-15 as INFORMATIONAL in the compatibility
   table (since they are known lossy / local-only)? Or include them with a flag column?
   (Recommendation: include with a flag column; the operator can filter on it.)
5. **Where do the report artifacts go** — `openspec/changes/matlab-version-e2e-compatibility/reports/`
   (alongside the SDD artifacts), or a fresh `e2e_runs/` at repo root, or
   `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/matlab_e2e/`?
   (Recommendation: under the change folder so they ship with the proposal-archive phase.)
6. **Test data scope** — single-subject (DPR_GWI007_DEP-MR-LOGGIA_MARCO) is the existing
   fixture. Should the E2E also run a second subject? Trade-off: doubles the runtime.
   (Recommendation: no — start with one; add a second only if the first is ambiguous.)

---

## Evidence Index

- Engram observation: `#267` — `sdd/entrypoint-divergence-diagnosis/coreg-runtime-drift` —
  isolated coregistration confirms MATLAB runtime drift; max affine 0.122425 between
  R2010b and R2026a on byte-identical input.
- Engram observations: `#244` through `#270` — investigation-cleanup-release phase outputs.
- Wiki: [[pseudo_ct_matlab_runtime_compatibility]] — runtime boundary and legacy-PCA
  documentation.
- Wiki: [[pseudo_ct_entrypoint_divergence_diagnosis]] — comparator and restart tooling.
- Wiki: [[pseudo_ct_dicom_comparator]] — NIfTI tolerance, sentinel guard, header drift.
- Wiki: [[pseudo_ct_attenuation_correction]] — pipeline architecture and entry points.
- Wiki: [[pseudo_ct_investigation_cleanup_release]] — release strategy and validation gate.
- OpenSpec `openspec/changes/entrypoint-divergence-diagnosis/exploration.md` — pipeline
  stages 1-15 with checkpoint artifacts.
- OpenSpec `openspec/changes/investigation-cleanup-release/explore.md` — full inventory
  of in-flight files and overlap surface.
- Source files (read for this exploration, not modified):
  `run_pseudo_CT_local.m`, `run_pseudo_CT_launchpad.m`, `src/core/atlas_based_attenuation_map.m`,
  `src/core/move_image_2_MNI.m`, `src/core/normalized_2_att_map.m`, `src/core/pseudo_ct_princomp_legacy.m`,
  `src/config/defaults_pseudo_CT.m`, `src/config/setup_pseudo_CT_paths.m`, `src/launchpad/batch_pseudo_CT_launchpad.m`,
  `scripts/diff_entrypoint_runs.m`, `scripts/restart_from_repos_checkpoint.m`,
  `scripts/sweep_smoothing_fwhm.m`, `scripts/run_tests.m`, `CHANGELOG.md`,
  `openspec/changes/entrypoint-divergence-diagnosis/{exploration.md,verify-report.md,tasks.md}`,
  `openspec/changes/investigation-cleanup-release/{explore.md,proposal.md,tasks.md}`,
  `openspec/specs/entrypoint-divergence-diagnostics/spec.md`, `openspec/config.yaml`.
- External fixtures (not modified): `test_data_local/MR/{MPRAGE,UMAP}/*.dcm`,
  `test_data_local/MR_PET/`, `test_data_launchpad/MR_PET/`,
  `coreg_input_canonical.nii`, `coreg_input_711.nii`, `coreg_input_2026a.nii`,
  `coreg_result_711.mat`, `coreg_result_2026a.mat` (all under
  `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/`).
- MATLAB install survey: `/autofs/cluster/matlab/` has 30+ installs from R11 through R2026a;
  the relevant subset for this test is R2010b through R2026a (≈18 installs).

---

## Ready for Proposal

**Yes, conditional on coordination with the in-flight `investigation-cleanup-release` agent.**

The orchestrator should ask the user (or the other agent):

1. **Coordination checkpoint** — is the `docs/` folder acceptable for the procedure
   document, or should it live under `openspec/changes/matlab-version-e2e-compatibility/PROCEDURE.md`?
2. **Optional artifacts** — include the shell wrapper + report aggregator (recommended,
   ~250 lines total), or stop at the procedure document (~80 lines)?
3. **Version matrix scope** — start with R2010b, R2013b, R2018b, R2022b, R2026a
   (recommended), or include all 18 R2010b+ installs?
4. **PCA shim sweep** — run the matrix twice, once with `PSEUDOCT_USE_PRINCOMP=0` and
   once with `=1` (recommended), or once with the default only?

If all four are answered as recommended, the next phases are:
- `sdd-propose` — formalize the procedure + shell + report as a 3-artifact change.
- `sdd-spec` — write the spec deltas (one for the procedure contract, one for the
  report-format contract). Strict TDD remains `false` — the change produces
  documentation and a thin wrapper, not test code.
- `sdd-design` — sequence the artifact creation and the operator's first E2E run.
- `sdd-tasks` — one task per artifact (procedure, shell, report) plus a manual
  E2E run task.
- `sdd-apply` — write the three artifacts. Do NOT commit during the
  in-flight cleanup PR; either land the cleanup first, or stage this change as a
  follow-up commit on the same branch.
- `sdd-verify` — operator runs the E2E, produces the first `compatibility.csv` and
  `first_divergence.json`, attaches them to the change folder, and the verify
  report confirms the report format matches the spec.
- `sdd-archive` — close the change; merge no delta specs into main (the change
  is purely additive in `docs/`, `scripts/`, and `openspec/changes/`).

The change is well within the 800-line review budget and well within the
single-PR default delivery strategy.
