# Exploration: Investigation Cleanup Release

**Change name:** `investigation-cleanup-release`
**Engram topic_key:** `sdd/investigation-cleanup-release/explore`
**Project:** `pseudoct_standalone`
**Date:** 2026-07-13
**Status:** Explore — evidence collected, scope not yet proposed

---

## TL;DR

1. The MATLAB 7.11 ↔ compiled-Launchpad equivalence is **proven at the coregistration step** (max affine 0.0 on the controlled test). The same byte-identical input run on MATLAB R2026a diverges by max affine **0.122425** at `spm_run_coreg_estimate`, with every other variable held constant. The runtime is the only source of the late-stage divergence.
2. The pre-coreg transform was **restored by the PCA shim + `recenter_before_normalization = 'No'`**, so the legacy `_repos` geometry is now reproducible from the same source files. This is a pre-condition for legacy parity but it is not the cure for runtime drift.
3. The investigation left a meaningful, intentional footprint in the repo (keep-temp flag, comparator script, PCA wrapper, PBS-log diagnostic, runtime-scrub for FS, env-var SPM selector). That footprint should be **kept and versioned**, with one finding documented in `CHANGELOG.md`. A second wave of generated artifacts (sandbox dirs, sweep outputs, alternate SPM trees, scratch test data, an empty `package-lock.json`, an investigation cookbook script) should be **removed or gitignored** before the next release tag.
4. Release readiness: version bump, `CHANGELOG.md` entry describing the runtime-drift finding and the legacy-parity guidance, smoke + lint green, no untracked scratch inside the repo. The release itself is small; the work is mostly classification and cleanup.

---

## Verified Finding (the thing to document)

For **byte-identical** pre-coregistration NIfTI input, **same SPM sources / MEX / `coreg.estimate` options**, and **same r6313 SPM dependencies**:

| MATLAB runtime | `spm_run_coreg_estimate` result | Matches compiled Launchpad? |
|---|---|---|
| **MATLAB 7.11 (R2010b)** | matches `coreg_result_711.mat` | **YES — exact match** |
| **Compiled Launchpad v2.0** (MCR 7.11) | reference result | — |
| **MATLAB R2026a** | `coreg_result_2026a.mat` | **NO — max affine delta = 0.122425** |

Artifacts (outside the repo, under `pseudoCT_devel/`):
- `coreg_input_711.nii`, `coreg_input_2026a.nii` — byte-identical inputs
- `coreg_input_canonical.nii` — canonical source for both
- `coreg_result_711.mat`, `coreg_result_2026a.mat` — full `spm_run_coreg_estimate` results
- `coreg_result_*.mat` is the only variable between the two runs

This is **not** a PCA or `move_image_2_MNI` problem anymore. The PCA shim (`pseudo_ct_princomp_legacy.m` + `pseudo_ct_princomp` wrapper inside `move_image_2_MNI.m`) and the `recenter_before_normalization = 'No'` default together restore the legacy pre-coreg transform on the modern runtime. The remaining gap is in the optimizer/interpolator of `spm_run_coreg_estimate` itself, which differs between MATLAB 7.11 / MCR 7.11 and R2026a. The compiled Launchpad binary **is** MATLAB 7.11 / MCR 7.11 (it lives in `mrpet/standalone_apps/Pseudo_CT_launchpad` and was built Dec 2014, predating any R2010b+ runtime change).

> **Legacy-parity guidance** (what the next release should tell operators)
> - For **bit-exact** legacy match on the full pipeline, run the **local** pipeline on **MATLAB 7.11 / R2010b** (the only runtime that matches the compiled Launchpad v2.0 binary). Modern MATLABs (R2013b+) match the pre-coreg transform via the shim but diverge downstream at the optimizer.
> - `recenter_before_normalization` default flipped from `'Yes'` to `'No'` to restore the legacy pre-coreg transform. Operators who want the v1.8+ recenter behavior can set it back to `'Yes'` in `defaults_pseudo_CT.m`.
> - `PSEUDOCT_USE_PRINCOMP=1` forces the legacy `princomp` path (old `princomp` if available, else the repo-local `pseudo_ct_princomp_legacy.m` shim). Default is modern `pca(...)` for cleaner behavior on R2013b+.
> - `PSEUDOCT_FS_LIBSTDCPP_ROOT` defaults to `/autofs/cluster/matlab/current/sys/os/glnxa64` and is prepended to `LD_LIBRARY_PATH` for child FreeSurfer processes. Required to run `mri_normalize` from R2010b (the MCR 7.11 `libstdc++.so.6` lacks `GLIBCXX_3.4.11`).
> - `PSEUDOCT_SPM_VARIANT` / `PSEUDOCT_SPM_ROOT` switches the SPM tree at runtime. Default is `spm8-r6313`; the `spm8-dan` tree is for parity testing only and is not part of the release.
> - The compiled Launchpad v2.0 binary is the only currently-shipped cluster backend and is **not** rebuilt by this release. Any operator-facing divergence summary must keep saying "compiled binary unchanged; diagnosis is the operator's tool."

---

## Current State

### Repository snapshot

- Branch: `main` (clean at `0043999 fix: centralize changelog release metadata`, v2.6.1)
- 12 tracked files modified
- 16 untracked files / directories
- `dist/pseudoCT_v2.6.1/` is the most recent packaged release (already shipped as v2.6.1 in commit `0043999`); **does not** include any of the investigation's new diagnostic helpers.
- The repo has not been tagged since `0043999`. The new work is uncommitted.

### OpenSpec state

| State | Change | Notes |
|---|---|---|
| Archived | `2026-06-01-batch-discovery-messages`, `2026-06-01-pipeline-quality-fixes`, `2026-06-26-launchpad-matlab-compat`, `2026-06-30-umap-batchatlas-packaging`, `2026-07-07-extract-version-changelog` | All completed and shipped. |
| Active (spec only) | `batch-autodiscovery-observability`, `ute-umap-discovery`, `batch-atlas-resolution`, `launchpad-matlab-compat`, `release-packaging`, `entrypoint-divergence-diagnostics` | Source-of-truth specs; no corresponding open change folder. |
| Open change folder | `local-pipeline-end-compat/` (proposal/design/exploration/specs/tasks — no `verify-report.md`; tasks 2.x, 3.x unchecked) | Implementation in `atlas_based_attenuation_map.m` is uncommitted. |
| Open change folder | `entrypoint-divergence-diagnosis/` (all 5 phases) | Tasks 4.3, 4.4, 4.5 (manual E2E) are unchecked; everything else implemented but uncommitted. |
| Stale | `initial-survey/`, `pipeline-quality-fixes/` | Pre-OpenSpec-housekeeping; `pipeline-quality-fixes/` was already archived to `2026-06-01-pipeline-quality-fixes/`. |
| Stray | `extract-version-changelog/archive-report.md` (uncommitted) | Should be moved into `openspec/changes/archive/2026-07-07-extract-version-changelog/` or removed; the archive ran in engram mode and never moved the folder. |
| New (this change) | `openspec/changes/investigation-cleanup-release/` | This artifact is its first entry. |

### Investigation state (what was proven, what's still open)

**Proven (operator-grade evidence):**
- `MPRAGE_spm.nii` is byte-identical between local and Launchpad runs → DICOM→NIfTI is **not** a divergence point (`entrypoint-divergence-diagnosis/exploration.md:75`).
- `MPRAGE_spm_normalized.nii` diverges → first known divergent artifact.
- `att_map.nii` diverges → final artifact diverges.
- `recenter_before_normalization = 'No'` + `pseudo_ct_princomp_legacy` shim **restore the legacy pre-coreg transform** (the `_repos` geometry matches the Launchpad reference on R2026a).
- `PSEUDOCT_KEEP_TMP=1` plumbing preserves `MR_PET/tmp/` end-to-end (entry, launchpad, cluster-scratch) so re-runs are reproducible.
- `diff_entrypoint_runs.m` correctly identifies first-divergent files using a 4-tier status model (`IDENTICAL`, `HEADER_ONLY_DIFF`, `VOXEL_DIVERGENT`, `DIVERGENT`) with inside/outside-head metrics.
- `spm_run_coreg_estimate` runtime drift is **isolated to the MATLAB runtime** itself (Engram #267).

**Not yet proven (open work, not a release blocker):**
- The 3 manual end-to-end checks for `entrypoint-divergence-diagnosis` (tasks 4.3, 4.4, 4.5) still need an operator with both test datasets, FreeSurfer 5.3, and cluster SSH.
- The `local-pipeline-end-compat` change has **not been verified at runtime** — no `verify-report.md` exists, and tasks 2.x and 3.x are unchecked. The change is in `openspec/changes/local-pipeline-end-compat/` but the source edit is uncommitted.
- Denoised-NIfTI Launchpad support is still an open question (see `TODO.md`).
- GUI callback compatibility with `PSEUDOCT_SPM_VARIANT=dan` is broken (`TODO.md`) but a workaround exists.

### Engram evidence of the investigation

- `#267` (2026-07-13): Isolated coregistration confirms MATLAB runtime drift. Verified max affine 0.122425; iteration trajectories differ immediately. Topic: `sdd/entrypoint-divergence-diagnosis/coreg-runtime-drift`.
- Multiple observations on PCA shim, PBS log capture, SPM tree switching, `LD_LIBRARY_PATH` patching, and NIfTI comparator hardening. All under `pseudoct_standalone` / project scope.

---

## Affected Areas (evidence-based, not scope-deciding)

### Tracked modifications (intentional, in-flight, should ship in the next release)

| File | Why it's affected |
|---|---|
| `run_pseudo_CT_local.m` | `button='Yes'` → `should_cleanup` boolean; calls `pseudo_CT_keep_temp_enabled`. |
| `run_pseudo_CT_launchpad.m` | Same `should_cleanup` gate; passes `'keep_tmp',1/0` to batch. |
| `src/launchpad/batch_pseudo_CT_launchpad.m` | New `keep_tmp` name-value arg; gates cluster-side `rm -rf`; **always-on PBS log capture** (renamed subject-prefixed `_launchpad_*` files in `MR_PET/tmp/`); failure-path now references the saved PBS logs. |
| `src/config/defaults_pseudo_CT.m` | `recenter_before_normalization = 'No'` (was `'Yes'`) + `keep_temp_files = 'No'`. |
| `src/config/defaults_pseudo_CT_launchpad.m` | Adds `keep_temp_files = 'No'`. |
| `src/config/setup_pseudo_CT_paths.m` | Uses `pseudo_CT_resolve_spm_root` (env-driven SPM selector). |
| `src/core/move_image_2_MNI.m` | PCA wrapper: `pseudo_ct_princomp` → modern `pca` / legacy `princomp` / repo shim; `PSEUDOCT_USE_PRINCOMP=1` forces legacy; `PSEUDOCT_DEBUG_MOVE2MNI=1` writes sidecar `*_move2mni_debug.mat`. Fixed `_repos.nii` suffix construction. |
| `src/remote/run_normalization_cmd.m` | `LD_LIBRARY_PATH` scrubbing via `PSEUDOCT_FS_LIBSTDCPP_ROOT` for FreeSurfer child processes. |
| `scripts/run_smoke_tests.m` | +1023 lines: 2b/2c structural checks, 7a–7c behavioral tests (keep-temp env precedence, comparator text pipeline, MD5 sentinel guard, DICOM magic-byte dispatch, Launchpad diagnostic markers, FWHM sweep). |

### Untracked (intent-mixed — see Classification below)

| Path | Intent (evidence-based) |
|---|---|
| `TODO.md` | Operator's working notes (4 open items). User work. |
| `openspec/changes/entrypoint-divergence-diagnosis/` | OpenSpec change folder for the diagnosis work (all 5 phases; 4.3/4.4/4.5 unchecked). |
| `openspec/changes/extract-version-changelog/archive-report.md` | Stale archive report; the folder itself is missing from `archive/`. |
| `openspec/specs/entrypoint-divergence-diagnostics/` | The active spec folder for the diagnosis work; already in `git ls-files`? **No** — untracked. |
| `package-lock.json` | Empty `{}`. Accidental, MATLAB has no use for it. |
| `scripts/compare_hash_strings.m` | Comparator helper. |
| `scripts/compare_nifti_data.m` | Comparator core. |
| `scripts/diff_entrypoint_runs.m` | Comparator entry point. |
| `scripts/restart_from_repos_checkpoint.m` | Diagnostic restart script. |
| `scripts/run_tests.m` | Operator cookbook (not a test file). |
| `scripts/sweep_smoothing_fwhm.m` | FWHM sweep diagnostic. |
| `spm8-dan/` (1.1 GB) | Alternate SPM tree used for parity testing; not for release. |
| `src/config/pseudo_CT_keep_temp_enabled.m` | Resolver helper. |
| `src/config/pseudo_CT_resolve_spm_root.m` | SPM-tree resolver helper. |
| `src/core/normalized_2_att_map.m` | Diagnostic helper (sandboxed downstream restart). |
| `src/core/pseudo_ct_princomp_legacy.m` | Legacy PCA shim. |

### Outside the repo (under `pseudoCT_devel/`)

| Path | Intent |
|---|---|
| `coreg_input_*.nii`, `coreg_input_canonical.nii` | The controlled test inputs. The *result* is the finding; the inputs are reproducible from the same `mri_normalize` step in either pipeline. |
| `coreg_result_711.mat`, `coreg_result_2026a.mat` | **The evidence** of the finding. Should be promoted to a documented artifact or archived in the change folder, not left as a loose top-level pair. |
| `fwhm_sweep/`, `restart_sandbox_*/` | Sandbox output of the diagnostic scripts. Transient. |
| `test_data_launchpad-10-Jul-2026/`, `test_data_local-10-Jul-2026/`, `test_data_local-LEGACYSHIM/`, `test_data_local-PCA/` | Experimental dataset variants created by diagnostic re-runs. Not source-of-truth. |

---

## Classification (keep / document / remove / ignore)

> Per the user's instruction: do not decide scope beyond evidence; explicitly distinguish tracked modifications from generated/untracked experimental artifacts; preserve user work. The table below is **evidence-based**, not a commitment to act.

| Path | Class | Why (evidence) |
|---|---|---|
| `run_pseudo_CT_local.m`, `run_pseudo_CT_launchpad.m` | **Keep (track)** | Cleanly aligned with `entrypoint-divergence-diagnosis` tasks 2.1, 2.2; passed smoke + behavioral tests. |
| `src/launchpad/batch_pseudo_CT_launchpad.m` | **Keep (track)** | Tasks 2.3, 5.0 work; PBS log diagnostic is reproducible per Engram observations. |
| `src/config/defaults_pseudo_CT.m`, `defaults_pseudo_CT_launchpad.m` | **Keep (track)** | Tasks 1.1, 1.2; `recenter` flip is part of legacy-parity fix. |
| `src/config/setup_pseudo_CT_paths.m` | **Keep (track)** | Required for the SPM-tree selector; matches `pseudo_CT_resolve_spm_root` helper. |
| `src/core/move_image_2_MNI.m` | **Keep (track)** | PCA wrapper + debug hook; the shim is what restores pre-coreg parity. |
| `src/remote/run_normalization_cmd.m` | **Keep (track)** | `LD_LIBRARY_PATH` scrub is required for R2010b to run `mri_normalize`; documented in `TODO.md` and Engram. |
| `scripts/run_smoke_tests.m` | **Keep (track)** | +1023 lines of structural + behavioral coverage; necessary for CI. |
| `src/config/pseudo_CT_keep_temp_enabled.m` | **Keep (track)** | Required for tasks 1.3, 2.1, 2.2. |
| `src/config/pseudo_CT_resolve_spm_root.m` | **Keep (track)** | Required for env-driven SPM tree selection. |
| `src/core/pseudo_ct_princomp_legacy.m` | **Keep (track)** | The shim that makes pre-coreg parity reproducible on R2013b+. |
| `src/core/normalized_2_att_map.m` | **Document (keep)** | Diagnostic-only helper, but useful for future re-investigation. Either ship as documented diag or leave untracked with a clear "not for release" note. |
| `scripts/compare_hash_strings.m` | **Keep (track)** | Comparator core; has runtime-tested sentinel guard. |
| `scripts/compare_nifti_data.m` | **Keep (track)** | Comparator core; no file I/O, independently testable. |
| `scripts/diff_entrypoint_runs.m` | **Keep (track)** | Comparator entry point; spec'd in `entrypoint-divergence-diagnostics/spec.md`. |
| `scripts/sweep_smoothing_fwhm.m` | **Document (keep)** | FWHM-sweep diagnostic; only run by humans. Could move to `scripts/diagnostics/`. |
| `scripts/restart_from_repos_checkpoint.m` | **Document (keep)** | Sandbox-restart diagnostic; needed to re-derive the finding. |
| `scripts/run_tests.m` | **Remove** | Operator cookbook (not a test file); re-typing ad-hoc commands. Should not be tracked. |
| `TODO.md` | **Keep (track)** | User's open work; contains legitimate follow-ups (FS child lib, GUI compat, console log capture, denoised NIfTI). |
| `openspec/changes/entrypoint-divergence-diagnosis/` | **Keep (track)** | All 5 phase artifacts produced. Manual E2E tasks 4.3/4.4/4.5 remain open — `verify-report.md` already says PASS WITH WARNINGS. |
| `openspec/changes/extract-version-changelog/archive-report.md` | **Remove or fix** | The `extract-version-changelog` change's archive report is in the wrong place; the corresponding folder was never moved into `archive/`. Clean up to avoid future confusion. |
| `openspec/specs/entrypoint-divergence-diagnostics/` | **Keep (track)** | Active main spec; the diagnosis artifacts depend on it. |
| `package-lock.json` | **Remove** | Empty `{}`; MATLAB has no use for it. Almost certainly an accident. |
| `spm8-dan/` (1.1 GB) | **Ignore** | Add to `.gitignore`; it's an alternate SPM tree used for parity testing, not for the release. |
| `.atl/.skill-registry.cache.json`, `.atl/skill-registry.md` | **Ignore** | Auto-regenerated; the change is the `Last updated` bump and `opencode-quota/` line. Could revert the cache edit and keep only the `.md`/`.gitignore` edits. |
| `.gitignore` | **Keep (track)** | The `opencode-quota/` addition is intentional; the `spm8-dan/` ignore should be added by this change. |
| `coreg_input_*.nii`, `coreg_input_canonical.nii` (outside repo) | **Ignore or document** | Reproducible from the same pipeline step. The *finding* is the value, not the inputs. |
| `coreg_result_711.mat`, `coreg_result_2026a.mat` (outside repo) | **Document** | The evidence. Either copy into a change-folder evidence subdir or reference from the CHANGELOG entry with a hash. |
| `fwhm_sweep/`, `restart_sandbox_*/` (outside repo) | **Remove** | Transient sandbox output; reproducible from the scripts. |
| `test_data_*-10-Jul-2026/`, `test_data_local-LEGACYSHIM/`, `test_data_local-PCA/` (outside repo) | **Ignore** | Experimental data variants; original `test_data_local/` and `test_data_launchpad/` are the only true sources. |

---

## Approaches (for the release strategy)

### 1. Minimal: commit the diagnosis change, add a `CHANGELOG.md` entry, then a small release

- Commit the in-flight work as `entrypoint-divergence-diagnosis` (treat the 3 manual E2E tasks as already-PASS-WITH-WARNINGS, per the existing verify report). Add a `CHANGELOG.md` line under a new version describing the runtime-drift finding and the legacy-parity guidance. Tag as v2.6.2.
- **Pros:** Smallest change; aligns with the existing archive pattern (engram `archive-report.md` + tag + push, as in v2.6.1).
- **Cons:** Leaves `spm8-dan/`, `package-lock.json`, the cookbook `scripts/run_tests.m`, the stray `archive-report.md`, and the `local-pipeline-end-compat` change uncommitted. The repo is "released" but not "clean."
- **Effort:** Low.

### 2. Recommended: cleanup-first, then commit, then release

- **Phase 1 — Cleanup (no semantic change):**
  - `git rm` or delete: `package-lock.json`, `scripts/run_tests.m`, `openspec/changes/extract-version-changelog/archive-report.md` (move into `archive/2026-07-07-extract-version-changelog/` or delete).
  - `echo "spm8-dan/" >> .gitignore`; do **not** `git rm` the tree (it's untracked).
  - Decide on `src/core/normalized_2_att_map.m`, `scripts/sweep_smoothing_fwhm.m`, `scripts/restart_from_repos_checkpoint.m`: keep as documented diagnostics (single commit) or move into `scripts/diagnostics/` and `src/core/diagnostics/`.
  - Decide on `TODO.md`: track it (small; aligns with `AGENTS.md`); or keep it untracked but documented.
  - Promote `coreg_result_711.mat` / `coreg_result_2026a.mat` into the change folder as `evidence/`, or hash them and reference from `CHANGELOG.md`.
- **Phase 2 — Commit the diagnosis change:** `entrypoint-divergence-diagnosis` with the open `verify-report.md`'s PASS-WITH-WARNINGS verdict intact.
- **Phase 3 — Commit the QC-tiff compat change:** `local-pipeline-end-compat` — 5-removal/1-addition single-file change. Either (a) run a real subject and produce a `verify-report.md` (preferred), or (b) reclassify as a follow-up and keep it in the change folder for the next cycle.
- **Phase 4 — `CHANGELOG.md` entry under a new version (2.6.2 or 2.7.0):** summarize the runtime-drift finding, the legacy-parity guidance, the new env vars (`PSEUDOCT_KEEP_TMP`, `PSEUDOCT_USE_PRINCOMP`, `PSEUDOCT_FS_LIBSTDCPP_ROOT`, `PSEUDOCT_SPM_VARIANT` / `PSEUDOCT_SPM_ROOT`, `PSEUDOCT_DEBUG_MOVE2MNI`), and the operator note that the compiled Launchpad v2.0 binary is unchanged.
- **Phase 5 — Tag and release:** tag as v2.6.2, `make package`, archive both SDD changes via `sdd-archive` (this engram artifact will be superseded by the archive report).
- **Pros:** Clean repo on the release commit. The CHANGELOG entry gives the finding the durability the user asked for.
- **Cons:** The 3 manual E2E tasks (4.3, 4.4, 4.5) and the `local-pipeline-end-compat` runtime verification are still open. Either operator-runs-them-now or `verify-report.md` carries the WARNING forward explicitly.
- **Effort:** Medium (≈5–7 commits; ~600 changed lines including new scripts; well under the 800-line budget).

### 3. Heavy: split into a chained release with `local-pipeline-end-compat` first

- PR 1: `local-pipeline-end-compat` (≈6 changed lines) — cherry-pick the uncommitted edit, ship, tag.
- PR 2: `entrypoint-divergence-diagnosis` (≈600 lines including scripts) — ships the keep-temp/comparator/PCA/launchpad-diagnostic stack.
- PR 3: `investigation-cleanup-release` itself — cleanup, `CHANGELOG.md`, `dist/` regen, tag v2.6.2.
- **Pros:** Each PR is small; review is easier; rollback is per-PR.
- **Cons:** Three PRs for what is essentially one logical release. The repo is already a single-branch / single-PR-cadence project (see `extract-version-changelog` archive — single PR, low risk).
- **Effort:** High. Probably not justified for the current change profile.

### 4. Operator-action: re-run E2E before any release

- Before tagging, run `run_pseudo_CT_local` and `run_pseudo_CT_launchpad` on `test_data_*` with `PSEUDOCT_KEEP_TMP=1` (tasks 4.3, 4.4 of the diagnosis change), then `run_pseudo_CT_local` on R2026a to confirm the QC TIFF fix. Update the `verify-report.md` for both changes to remove the WARNINGs. Then approach 2.
- **Pros:** Cleanest release. Removes the "manual E2E still open" caveat.
- **Cons:** Requires real data + MATLAB access; not always feasible.
- **Effort:** Operator time, not author time.

---

## Recommendation

**Approach 2 (cleanup-first, then commit, then release), gated on Approach 4 if the operator can do the E2E runs before tagging.**

Specifically:
1. **Cleanup (commit group 1):** `package-lock.json` removal, `.gitignore` adds for `spm8-dan/` and any other reproducible-but-large untracked trees, the stray `archive-report.md` relocation, the `scripts/run_tests.m` removal. No semantic change. One or two small commits.
2. **Document the runtime-drift finding in `CHANGELOG.md` (commit group 2).** The entry is the durable deliverable; it should lead with the verified finding (MATLAB 7.11 == compiled Launchpad at coreg; R2026a diverges at `spm_run_coreg_estimate`; PCA shim restored pre-coreg parity; the divergence is runtime-only), then list the env vars and their purpose, then state "compiled Launchpad v2.0 binary unchanged."
3. **Commit the two open changes** (`entrypoint-divergence-diagnosis`, `local-pipeline-end-compat`) as documented in their `tasks.md`. Keep the WARNINGs from `entrypoint-divergence-diagnosis/verify-report.md` explicit; either resolve them via Approach 4 first or carry them forward into the release notes.
4. **Tag v2.6.2** (or 2.7.0 if the runtime-drift finding is considered user-visible behavior change). Run `make package`. Archive both SDD changes via `sdd-archive`.
5. **Promote the coreg evidence** (`coreg_result_711.mat`, `coreg_result_2026a.mat`, the canonical input, a short text report of the max affine delta) into `openspec/changes/investigation-cleanup-release/evidence/` or attach hashes to the `CHANGELOG.md` entry, so the finding is reproducible from the repo alone.

Why this approach:
- The investigation produced **evidence**, not a behavior change. The release is mostly "make the evidence durable and the repo clean."
- The `CHANGELOG.md` entry is the smallest possible durable form of the user's request to "document what we have found in an appropriate way."
- Single-PR cadence matches the project's history (v2.6.0, v2.6.1 were each one PR). Review budget is well under 800 lines for cleanup + two small change commits.
- The PCA shim and runtime-scrub already work; the keep-temp/comparator stack already passes smoke. The only NEW work for the release is the CHANGELOG entry and the cleanup commits.

---

## Release Readiness Checklist (evidence-based, not a commitment)

- [ ] **Version**: decide between v2.6.2 (behavior-preserving + new diagnostic tooling) and v2.7.0 (runtime-drift finding is user-visible). Evidence: the compiled Launchpad v2.0 binary is unchanged; the local path now runs correctly on R2010b via the shim/scrub stack; the local path diverges on R2026a (documented).
- [ ] **`CHANGELOG.md` entry**: lead with the verified finding, list the new env vars (`PSEUDOCT_KEEP_TMP`, `PSEUDOCT_USE_PRINCOMP`, `PSEUDOCT_FS_LIBSTDCPP_ROOT`, `PSEUDOCT_SPM_VARIANT` / `PSEUDOCT_SPM_ROOT`, `PSEUDOCT_DEBUG_MOVE2MNI`), state "compiled Launchpad v2.0 binary unchanged," and reference the evidence files (mat + nifti + canonical input).
- [ ] **Verification**:
  - [ ] `run('scripts/run_smoke_tests.m')` — currently 90/90 pass + 2b/2c/7a/7b/7c/launchpad-diag structural checks.
  - [ ] `run('scripts/run_lint.m')` — no new mlint issues on changed lines.
  - [ ] Manual E2E (operator): tasks 4.3, 4.4, 4.5 of `entrypoint-divergence-diagnosis` — one real-subject run on each entrypoint with `PSEUDOCT_KEEP_TMP=1`; one real-subject run on R2026a for the QC TIFF fix.
  - [ ] `make package` — regenerate `dist/pseudoCT_v2.6.2.tar.gz` and the unpacked `dist/pseudoCT_v2.6.2/`.
- [ ] **Commit readiness**:
  - [ ] Tracked modifications are reviewed and split into the two SDD change folders.
  - [ ] Untracked scratch (listed in the Classification table) is removed, gitignored, or promoted to evidence.
  - [ ] `package-lock.json` removed.
  - [ ] `spm8-dan/` added to `.gitignore`.
  - [ ] Stray `openspec/changes/extract-version-changelog/archive-report.md` resolved.
- [ ] **Archive**: both `entrypoint-divergence-diagnosis` and `local-pipeline-end-compat` get `sdd-archive` runs before the next change is opened, so the spec source-of-truth stays coherent.

---

## Risks

| Risk | Likelihood | Evidence / mitigation |
|---|---|---|
| `coreg_result_*.mat` is reproducible only on this MATLAB install | High | The max-affine-delta value is operator-install-specific. The *finding* (runtime drift exists) is portable; the *number* is not. Mitigate by hashing the files into the CHANGELOG entry and referencing the original scripts (`scripts/run_tests.m` is the cookbook, but it must be removed before the release — see Classification). |
| `TODO.md` items aren't tracked, so they vanish from history | Medium | Once `TODO.md` is tracked, it has the same durability as the rest of the repo. |
| `local-pipeline-end-compat` ships without runtime verification | Medium | Either resolve via Approach 4 (operator run), or carry the warning forward in the release notes and add a follow-up. The fix is small and the spec is clear; risk is low. |
| `spm8-dan/` accidentally gets committed (1.1 GB → repo bloat) | High if not gitignored | The `.gitignore` change is the mitigation. |
| Cleanup deletes a file the user is using | Low | The Classification table calls out each file's intent; nothing in "remove" is irreproducible. `package-lock.json` is empty; `scripts/run_tests.m` is an operator cookbook. |
| Reviewer expects a *root-cause* fix in the same release | Medium | The runtime drift cannot be fixed from this repo (it's in the MATLAB optimizer). The release says so explicitly. Document, don't fix. |
| Cleanup is bundled with the change and the PR is > 400 lines | Low | The cleanup group is small (~50 changed lines across `.gitignore`, `package-lock.json` removal, `archive-report.md` relocation, `scripts/run_tests.m` removal). The two SDD changes together are well under 800. |
| `dist/pseudoCT_v2.6.1/` is now stale (does not include the new diagnostic helpers) | Medium | The next `make package` overwrites it. Decision: include the diagnostic helpers in the package or keep them out? They are documented; include in `dist/` if you want operators to use them. |

---

## Ready for Proposal

**Yes, conditional on one operator decision.** The orchestrator should ask the user:

1. **Version bump:** v2.6.2 (diagnostic tooling + finding documented, no behavior change for compiled Launchpad) or v2.7.0 (finding is treated as user-visible)?
2. **Diagnostic helpers in the shipped package:** include `scripts/diff_entrypoint_runs.m`, `src/core/pseudo_ct_princomp_legacy.m`, `src/core/normalized_2_att_map.m`, `scripts/restart_from_repos_checkpoint.m`, `scripts/sweep_smoothing_fwhm.m` in `dist/`, or keep them out of the runtime bundle (they'd still be in the repo)?
3. **Operator E2E before tag:** can the operator run tasks 4.3/4.4/4.5 + a R2026a QC TIFF verification on real data before the release, or do we carry the WARNINGs forward?
4. **Evidence promotion:** copy `coreg_result_711.mat`, `coreg_result_2026a.mat`, and the canonical input into `openspec/changes/investigation-cleanup-release/evidence/`, or just hash them into `CHANGELOG.md`?
5. **`spm8-dan/`:** add to `.gitignore` and leave in place (parity-testing convenience), or move out of the repo entirely?

Once those are answered, the next phases are:
- `sdd-propose` — formalize the cleanup + release plan with the chosen version and packaging decisions.
- `sdd-spec` (delta) — only if the answer to (1) is v2.7.0 and there's a behavior contract change worth recording; otherwise no new spec.
- `sdd-design` — sequence the commits and PR slices.
- `sdd-tasks` — one task per commit (cleanup-group, CHANGELOG entry, two SDD changes, tag).
- `sdd-apply` — execute.
- `sdd-verify` — confirm `make package` + `run_smoke_tests` + `run_lint` + (optionally) operator E2E.
- `sdd-archive` — close the change; merge delta specs if any.

---

## Evidence Index

- Engram observation: `obs-1cbe1b2011ceeb57` (MATLAB runtime drift, max affine 0.122425).
- Topic key: `sdd/entrypoint-divergence-diagnosis/coreg-runtime-drift`.
- Files referenced (outside repo, under `pseudoCT_devel/`):
  - `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/coreg_input_canonical.nii`
  - `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/coreg_input_711.nii`
  - `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/coreg_input_2026a.nii`
  - `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/coreg_result_711.mat`
  - `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/coreg_result_2026a.mat`
- Prior SDD artifacts that this change builds on:
  - `openspec/changes/entrypoint-divergence-diagnosis/` (all 5 phases)
  - `openspec/changes/extract-version-changelog/` (archived, supplies the `CHANGELOG.md` convention this release will extend)
  - `openspec/changes/local-pipeline-end-compat/` (proposal/design/tasks; no verify report yet)
- Existing main specs that constrain this change: `release-packaging`, `entrypoint-divergence-diagnostics`, `launchpad-matlab-compat`.
