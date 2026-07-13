# Exploration: Entrypoint Divergence Diagnosis

**Change name (user-provided):** "this project has 2 input points: run_pseudo_CT_launchpad.m and run_pseudo_CT_local.m The results obtained from the two entry point, while very similar, do not match exactly. I would like to find a way to indentify where they diverge."

**Slug:** `entrypoint-divergence-diagnosis`
**Engram topic_key:** `sdd/entrypoint-divergence-diagnosis/explore`
**Project:** `pseudoct_standalone`
**Date:** 2026-07-08

---

## Current State

The pseudo-CT pipeline has two entry points that share the same end-to-end workflow but diverge in how the heavy atlas processing is executed.

**Local path** — `run_pseudo_CT_local.m` calls `atlas_based_attenuation_map.m` directly in-process. FreeSurfer's `mri_normalize` is invoked either through `src/remote/run_normalization_cmd.m` (local-host path, when `HOSTNAME=127.0.0.1`) or via SSH+`run_launchpad_cmd` to the cluster.

**Launchpad path** — `run_pseudo_CT_launchpad.m` calls `src/launchpad/batch_pseudo_CT_launchpad.m`, which `scp_put`s the MPRAGE NIfTI to the cluster, runs a shell pipeline `mri_normalize ... && run_Pseudo_CT_launchpad.sh <MCR> <normalized.nii> <templates> 0 <check_aliasing> <defaults.mat>`, and `scp_get`s results back. The `run_Pseudo_CT_launchpad.sh` wrapper invokes a **compiled v2.0 binary** (`/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/`) — a 2014-era MATLAB Compiler build of `atlas_based_attenuation_map.m` pinned to the v2.0 codebase. We have no source-level access to that binary.

The shared workflow, in order:

1. `convert_dicom_i_2_nii` — DICOM → `<seed>.nii` in `MR_PET/tmp/`
2. FreeSurfer `mri_normalize` — produces `<seed>_normalized.nii` (cluster-side for launchpad, local for `127.0.0.1`)
3. `move_image_2_MNI` — reorient toward `ch2.nii`
4. SPM New Segment + DARTEL + inverse warp + reslice — produces `rc1..rc6`, `u_rc1*`, `w*Atlas*` in `MR_PET/tmp/`
5. `reduce_bone_segment` — cleans `rc*` tissue maps
6. `CT_2_att_map` — converts the warped `Atlas_rCT` to `att_map.nii` (still float32)
7. `head_mask_mprage` + mask/erode/dilate — refines soft-tissue gap fill (lines 622–644 of `atlas_based_attenuation_map.m`)
8. `pseudo_CT_write_mu_map_dicom` — converts `att_map.nii` → DICOM mu-map series into `MR/pseudo_muMAP/`
9. `quick_fusion_pseudo_ct` → `Fusion_MR_Pseudo_CT_validation.tiff` (local only — the compiled v2.0 binary does NOT generate this TIFF)
10. `pseudo_CT_write_version_log` — writes `Pseudo_CT_AC_Version.txt` from `CHANGELOG.md` (local only — the compiled v2.0 binary writes the OLD hardcoded v2.0 version text)
11. `pseudo_CT_promote_final_outputs` — copies `att_map.nii`, `MPRAGE_spm.nii`, `MPRAGE_spm_normalized.nii`, `Pseudo_CT_AC_Version.txt`, `Fusion_MR_Pseudo_CT_validation.tiff` to `MR_PET/`
12. Cleanup:
    - Local entry: `rmdir(temp_working_dir, 's')` at `run_pseudo_CT_local.m:239`
    - Launchpad entry: `rmdir(jobs(jj).temp_dir, 's')` at `run_pseudo_CT_launchpad.m:157` (and `ssh2_command('rm -rf ...', ...)` for the cluster-side `lc_path` at `batch_pseudo_CT_launchpad.m:129`)
    - Both: `pseudo_CT_cleanup_intermediates(pathr)` deletes `*ute*`, `*UTE*`, `*Atlas*`, `*seg8.mat`, `rp_mu*`, `new_segment*.mat`, `create_inverse*.mat`, `dartel_existing*.mat`, `*_repos.nii`

### Cleanup locations (exact)

- `run_pseudo_CT_local.m:238-242` — `button='Yes'` hardcoded → `rmdir(temp_working_dir, 's')` always fires after promotion
- `run_pseudo_CT_local.m:168` (function `local_run_subject`) — `temp_working_dir` is the `MR_PET/tmp` resolved by `pseudo_CT_resolve_output_dirs`
- `run_pseudo_CT_launchpad.m:156-161` — same pattern, `button='Yes'` hardcoded
- `run_pseudo_CT_launchpad.m:114` — `batch_pseudo_CT_launchpad(..., 'clean_folder', 0, ...)` is already called with `clean_folder=0` so the cluster-side `pseudo_CT_cleanup_intermediates` is skipped, BUT the entry-script's own `rmdir` still fires
- `src/launchpad/batch_pseudo_CT_launchpad.m:134-144` — `pseudo_CT_cleanup_intermediates` (only if `clean_folder` arg is true; currently hardcoded to `0` by the entry script, so this is dormant for the current invocation)
- `src/launchpad/batch_pseudo_CT_launchpad.m:129` — `ssh2_command('rm -rf %s', lc_path_parent/num2str(rand_fold))` always fires after `scp_get`

### Intermediate files (what `MR_PET/tmp/` should contain if we preserve it)

Verified by reading `atlas_based_attenuation_map.m:188-660`:

- `mprage.nii` (input seed, identical byte-for-byte between the two test_data)
- `mprage_normalized.nii` (FS `mri_normalize` output — **first likely divergence point**)
- `mmprage.nii` (from `move_image_2_MNI`)
- `smmprage.nii` (from `spm_smooth`, FWHM=4)
- `rc1mmprage.nii` … `rc6mmprage.nii` (New Segment tissue maps)
- `Prc_new(i).nii` (after `reduce_bone_segment`)
- `u_rc1mmprage.nii` (DARTEL flow field)
- `wAtlas_*_u_rc1mmprage.nii` (warped atlases)
- `rwAtlas_*_u_rc1mmprage.nii` (after final `spm_reslice`)
- `att_map_no_filled.nii`, `att_map.nii`
- `Fusion_MR_Pseudo_CT_validation.tiff` (local only)
- `Pseudo_CT_AC_Version.txt` (local: from CHANGELOG; launchpad: hardcoded v2.0)
- `new_segment_<date>_batch.mat`, `dartel_existing_template_<date>_batch.mat`, `create_inverse_warped_<date>_batch.mat`

### Empirical state of the two test_data directories

Cross-checked via `md5sum` on the provided `test_data_launchpad` and `test_data_local`:

| File | launchpad md5 | local md5 | Verdict |
|---|---|---|---|
| `MR/MPRAGE/*.dcm` | (208 files) | (208 files) | Identical content, same filenames, same byte count per file |
| `MR/UMAP/*.dcm` | (128 files) | (128 files) | Identical content, same filenames, same byte count per file |
| `MR/pseudo_muMAP/*.dcm` | (128 files) | (128 files) | Same filenames, same byte count — need byte-level confirm |
| `MR_PET/MPRAGE_spm.nii` | `5a1c16fa...` | `5a1c16fa...` | **IDENTICAL** → DICOM→NIfTI is NOT a divergence point |
| `MR_PET/MPRAGE_spm_normalized.nii` | `838290ac...` | `0e803733...` | **DIVERGES** → first known divergent artifact |
| `MR_PET/att_map.nii` | `723e9364...` | `bfb4868...` | **DIVERGES** → final result differs |
| `MR_PET/Pseudo_CT_AC_Version.txt` | v2.0 hardcoded text, 1309 B | Full CHANGELOG, 1981 B | Diverges (expected, both paths source the version differently) |
| `MR_PET/Fusion_MR_Pseudo_CT_validation.tiff` | ABSENT | present, 800278 B | Missing on launchpad (compiled v2.0 binary does not produce it) |
| `MR_PET/tmp/` | absent | absent | Both already cleaned — temp files lost |

The `MPRAGE_spm.nii` equality is the strongest signal: the divergence is NOT in the DICOM→NIfTI conversion or the DICOM mu-map re-encoding. It begins at or before the FreeSurfer `mri_normalize` step. The `MPRAGE_spm_normalized.nii` divergence is consistent with the well-known difference that the compiled v2.0 binary skips the `center_subject_in_image.m` recenter step introduced in v1.8 (Sept 3, 2014) — a hypothesis to verify, not a confirmed cause.

---

## Affected Areas

- `run_pseudo_CT_local.m:238-242` — local rmdir block; must be guarded or commented for diff
- `run_pseudo_CT_launchpad.m:156-161` — launchpad rmdir block; must be guarded or commented for diff
- `src/launchpad/batch_pseudo_CT_launchpad.m:129` — `ssh2_command('rm -rf %s', lc_path)` for the cluster-side folder; cannot be reached from the local repo but the locally-copied files survive in `MR_PET/tmp/` so it is observable
- `src/launchpad/batch_pseudo_CT_launchpad.m:134-144` — `pseudo_CT_cleanup_intermediates` (currently dormant because `clean_folder=0`)
- `src/io/pseudo_CT_cleanup_intermediates.m` — deletes `*ute*`, `*UTE*`, `*Atlas*`, `*seg8.mat`, `rp_mu*`, `new_segment*.mat`, `create_inverse*.mat`, `dartel_existing*.mat`, `*_repos.nii`; NOT called from either entry script directly (it is called from `batch_pseudo_CT_launchpad.m:142` and was historically called by the local path before the v2.5 repackage)
- `src/core/atlas_based_attenuation_map.m:264-267` — `recenter_before_normalization` gate (lines 256–270); this is the single most likely behavioural divergence between the local v2.6.1 source and the compiled v2.0 binary
- `src/core/atlas_based_attenuation_map.m:90-104` — code version read from `CHANGELOG.md` (local only; the compiled v2.0 binary hardcodes v2.0)
- `src/core/atlas_based_attenuation_map.m:660-661` — `quick_fusion_pseudo_ct` (local only; compiled v2.0 binary lacks it)
- `src/core/atlas_based_attenuation_map.m:670-673` — `pseudo_CT_write_version_log` (local only; compiled v2.0 binary lacks it)
- `src/config/defaults_pseudo_CT.m:11` — `HOSTNAME = '127.0.0.1'` so the local path runs FreeSurfer commands locally through `src/remote/run_normalization_cmd.m`, NOT over SSH
- `src/config/defaults_pseudo_CT_launchpad.m:19` — `HOSTNAME = '172.27.25.134'`, `cluster = 'Yes'` so the launchpad path always SSHes to the cluster for `mri_normalize`
- `src/launchpad/run_normalization_cmd.m` vs `src/launchpad/run_launchpad_cmd.m` — the `is_local_host` branch in `atlas_based_attenuation_map.m:329-342` decides which one is used; when `127.0.0.1`, `run_normalization_cmd` invokes the local FreeSurfer binary with the same `mri_normalize ...` shell command

### Risks of the compiled v2.0 Launchpad backend visibility

- We have NO source access to the compiled binary. Any divergence caused by code in that binary (e.g., differences in `center_subject_in_image` behavior, `CT_2_att_map` coefficients, atlas versions) can only be diagnosed by side effects — i.e., by comparing the OUTPUT files it produces, not by reading source.
- `Batch_atlas/` is gitignored; if the compiled binary was linked against a DIFFERENT atlas set than the local `Batch_atlas/`, that would cause a global divergence. This is unlikely (the binary lives in `/autofs/cluster/pubsw/.../Batch_atlas` per `defaults_pseudo_CT_launchpad.m:28`) but should be checked by comparing the `Atlas_*` NIfTI files the local pipeline reads against what the binary reads. The compiled binary's atlas path is hardcoded into the v2.0 build; it cannot be re-pointed without rebuilding the binary.
- The `defaults_pseudo_CT_package_deployed.mat` (referenced in `defaults_pseudo_CT_launchpad.m:29`) is a MATLAB serialization of the v2.0 defaults — we cannot modify it from the local repo.

---

## Approaches

### 1. User's proposed strategy: inject code + comment out cleanup + diff script (literal)

- **Description:** Edit both entry scripts to skip the rmdir and `pseudo_CT_cleanup_intermediates`, run both pipelines on the test datasets, and write a custom MATLAB/Python diff over the preserved `MR_PET/tmp/` trees.
- **Pros:** Direct, no flag plumbing, the user already has the data and the fix in mind. Easy to revert.
- **Cons:**
  - The compiled v2.0 binary's cluster-side `/cluster/scratch/monday/<user>/<rand_fold>/` intermediate files are deleted at `batch_pseudo_CT_launchpad.m:129` AFTER `scp_get`. The `scp_get` at line 91 brings them to `temp_dir` (which is `MR_PET/tmp/`), so they ARE preserved in the local copy — but only because `scp_get` copies the FULL cluster folder listing. If a file is produced on the cluster but NOT in that listing, it is lost. To be safe we should also gate the cluster-side `rm -rf` at line 129 (requires an extra arg or comment).
  - The compiled v2.0 binary writes a different `Pseudo_CT_AC_Version.txt` content (it doesn't know about CHANGELOG.md) and does NOT write `Fusion_MR_Pseudo_CT_validation.tiff`. These are KNOWN, expected differences and should be excluded from the diff.
  - "Inject temporary code + comment out cleanup" leaves dead comments in the code that must be cleaned up before the proposal-archive phase. Lint will flag the commented `rmdir` blocks.
  - Cleanup is a side effect of MULTIPLE sites (entry-script rmdir, `pseudo_CT_cleanup_intermediates`, cluster-side `rm -rf`). A single comment-out can miss one and the diff will be incomplete.
- **Effort:** Low (one off-the-shelf diff over two directories)

### 2. Recommended: add a `PSEUDOCT_KEEP_TMP` debug flag (functional, not ad-hoc)

- **Description:** Add a single env-var or `defaults_pseudo_CT` setting `PSEUDOCT_KEEP_TMP=1` that:
  - Skips the `rmdir(temp_working_dir, 's')` block at `run_pseudo_CT_local.m:238-242` and the equivalent at `run_pseudo_CT_launchpad.m:156-161`.
  - Skips the call to `pseudo_CT_cleanup_intermediates` (when `clean_folder=0` already does this for launchpad, but local has no equivalent gate — confirmed by reading both entry scripts).
  - Also skip the cluster-side `ssh2_command('rm -rf %s', lc_path)` at `batch_pseudo_CT_launchpad.m:129` by adding a parallel `keep_tmp` arg plumbed through the entry script → `batch_pseudo_CT_launchpad` (same `name-value` arg pattern as `clean_folder` and `check_aliasing`).
  - Optionally write a `*_DIAGNOSIS.txt` file at the end of each run listing the full `MR_PET/tmp/` tree (helps the diff script).
- **Pros:**
  - Reversible (unset the flag and behavior reverts). No dead commented code, no lint damage.
  - Production users never see it unless they set the flag.
  - Same mechanism works for both paths; no need for per-script edits.
  - Plays nicely with the existing `clean_folder` arg infrastructure.
- **Cons:**
  - Touches four files (two entry scripts, `batch_pseudo_CT_launchpad.m`, possibly a new `defaults_pseudo_CT.m` field). Each is a small change.
  - Requires defining the flag contract (env var vs. defaults field vs. `varargin`).
  - The compiled v2.0 binary's INTERNAL cleanup still runs — but it only writes to the cluster-side `lc_path`, which we now preserve, and `scp_get` has already pulled everything we need to `MR_PET/tmp/`.
- **Effort:** Medium (small, well-scoped change to four files; ~30–50 lines including helper)

### 3. Hybrid: env-var flag for cleanup, plus a dedicated diff script in `scripts/`

- **Description:** Combine approach 2 with a `scripts/diff_entrypoint_runs.m` (or `diff_entrypoint_runs.py`) that:
  - Takes two `MR_PET/tmp/` directories as input.
  - Lists files by sorted name and pair-wise compares:
    - `.nii` → `spm_vol` for header, `spm_read_vols` for pixel data with a configurable tolerance (default 1e-6 for float32, 1e-3 for atlas float outputs). Also reports `max(abs(A-B))` and the count of voxels exceeding tolerance.
    - `.mat` → `load` and recursive field-by-field comparison (skipping fields with paths or timestamps).
    - `.dcm` → DICOM header diff (PatientID, StudyDate, etc.) and pixel diff.
    - `.tiff` → pixel diff via MATLAB `imread` or Python `tifffile`.
    - text logs → byte-level (md5) plus naive diff.
  - Returns a sorted "first divergence" report: which file in alphabetical step order first differs.
  - Also flags KNOWN expected differences (the v2.0 version text, the missing TIFF) so the user is not misled.
- **Pros:** Reproducible, reusable for future runs, no ad-hoc one-off. Pairs naturally with the flag from approach 2.
- **Cons:** The diff script is itself a piece of code that needs review. Edge cases (NaN in atlas masks, large NIfTI memory load) need thought. ~150–200 lines.
- **Effort:** Medium (single new script file, plus wiring into the existing `scripts/` folder)

---

## Recommendation

**Approach 2 + 3 combined: add a `PSEUDOCT_KEEP_TMP` flag AND a `scripts/diff_entrypoint_runs.m` comparison script.**

Rationale:

1. The user's proposed strategy (approach 1) works but leaves commented-out code and a one-off diff. A flag is cleaner, reversible, and aligns with the project's existing pattern (`clean_folder` and `check_aliasing` are already plumbed through `batch_pseudo_CT_launchpad.m:23-32`).
2. Once the flag exists, the diff script is a one-shot reusable tool that we will want every time we touch the pipeline.
3. The flag must be honored at THREE sites (local entry, launchpad entry, cluster-side cleanup at `batch_pseudo_CT_launchpad.m:129`). All three already have the structural pattern of "skip if env/arg says so"; we extend, not invent.
4. The diff methodology MUST be tolerance-based, not byte-level, for NIfTI pixel data. Byte-level is fine for `.mat` SPM batch templates (they embed only paths, no randomness — confirmed by reading the file generate at `atlas_based_attenuation_map.m:457-458, 513-514, 539-540`). DICOM pixel data MUST be tolerance-compared (the mu-map DICOM re-encoding at `pseudo_CT_write_mu_map_dicom.m` will not be bit-exact between two runs of the same pipeline).
5. Because the compiled v2.0 binary is opaque, we treat its output as a "black-box reference" and compare all local intermediate files against it AFTER the `scp_get` brings them to `MR_PET/tmp/`. We do NOT need to crack open the binary.

### Concrete plan for the next phases (proposal/spec/tasks)

The change becomes a two-task change:

- **Task A — preserve-tmp flag** (≤50 lines)
  - Add `keep_tmp` (or `PSEUDOCT_KEEP_TMP` env) handling to:
    - `run_pseudo_CT_local.m` (rmdir gate)
    - `run_pseudo_CT_launchpad.m` (rmdir gate)
    - `batch_pseudo_CT_launchpad.m` (new `name-value` arg like `clean_folder`, plus honor it at the cluster-side `rm -rf` line 129)
  - Add a smoke-test check that with `keep_tmp=1`, `MR_PET/tmp/` survives after a run.

- **Task B — diff script** (≤200 lines)
  - `scripts/diff_entrypoint_runs.m`: takes two root directories, walks `MR_PET/tmp/`, and produces a report. Honors a known-expected-differences list. Writes output to a file the user can inspect.
  - Optionally: thin Python wrapper if MATLAB is unavailable on the user's workstation.

- **Task C — first-run investigation** (NO new code, manual)
  - Run BOTH pipelines on `test_data_*` with `keep_tmp=1`, run the diff script, identify the FIRST divergent file (predicted: `MPRAGE_spm_normalized.nii` already diverges in the final state, so the FIRST intermediate divergence is somewhere in `MR_PET/tmp/` — likely the FS `mri_normalize` output or the `move_image_2_MNI` output).
  - Hand the report to the user for root-cause analysis. This is the "Once the first divergent file is identified, trace back to where it is generated and understand the cause" step from the user's original prompt.

---

## Risks

- **Compiled binary is opaque.** We cannot fix a divergence caused inside the v2.0 binary from this repo. The diagnosis is to *identify* the divergence, not to fix it; the user may decide whether to rebuild the binary.
- **`Batch_atlas/` is gitignored.** The local repo's `Batch_atlas/` and the compiled binary's `Batch_atlas/` (at `/autofs/cluster/pubsw/.../Batch_atlas`) might differ. Before declaring any "first divergence", diff the atlas NIfTI files between the two locations. **Action item for the proposal: have the user run a quick `diff` on `Batch_atlas/Atlas_*.nii` between the local path and the cluster path.**
- **DICOM mu-map re-encoding is lossy.** `pseudo_CT_write_mu_map_dicom.m` (line 114) calls `convert_dicom_i_2_nii` on the UMAP reference; subsequent pixel writes use scaled integers. Even two runs of the SAME pipeline on the same input will not be bit-exact in the mu-map. Diff with a tolerance, not byte-level.
- **SPM randomness.** SPM New Segment and DARTEL use RNG. By default they are deterministic for a given MATLAB/SPM version, but a MATLAB version bump between the two test runs (or between the local v2.6.1 build and the compiled v2.0 binary) WILL introduce divergence that is purely numerical, not semantic. Document the MATLAB version in the diff report.
- **FreeSurfer version drift.** The local path uses `fs_setenv_530_from_launchpad.sh` (FS 5.3). If the cluster's `/usr/local/freesurfer/stable5_3_0` has been silently upgraded, the `mri_normalize` output will diverge even between two runs of the SAME pipeline. Verify FS versions before drawing conclusions.
- **Cleanup is multi-site.** Missing one site (e.g., the cluster-side `rm -rf` at `batch_pseudo_CT_launchpad.m:129`) means the diff sees a truncated launchpad `MR_PET/tmp/`. The diff script should report file counts and warn if they differ between sides.
- **Test data has no `MR_PET/tmp/` already.** The user must re-run both pipelines with `keep_tmp=1` set; the provided `test_data_*` directories are post-cleanup. This is fine, but means the diagnosis cannot start until a flag-and-rerun cycle is complete.
- **Review budget.** A diff script + 3 small entry-script edits is well under the 800-line budget; no chained PR needed. Single PR is fine.

---

## Open Questions / Assumptions for the Proposal Phase

1. **Flag mechanism** — env var (`PSEUDOCT_KEEP_TMP=1`) or `defaults_pseudo_CT` field, or both? Recommendation: env var only, to keep the defaults file free of debug-only knobs.
2. **Should the cluster-side `rm -rf` be gated or just left as-is?** Leaving it as-is means we lose visibility into cluster-side leftovers, but `scp_get` already brought everything we need. Recommendation: gate it via the new `keep_tmp` arg.
3. **Should `pseudo_CT_cleanup_intermediates` be called at all when `keep_tmp=1`?** Currently the local entry script does not call it (only the launchpad path did, and it is hardcoded to `clean_folder=0` by the entry). So this is a no-op for both paths. Recommendation: skip the question; document the current behavior in a comment.
4. **Diff script language — MATLAB or Python?** MATLAB is consistent with the rest of the project and can use `spm_vol`/`spm_read_vols` natively. Python requires `nibabel` (probably not installed on the cluster). Recommendation: MATLAB.
5. **Known-expected-differences list** — should it be a code constant in the diff script, or a sidecar JSON/YAML? Recommendation: code constant initially; promote to a config file only if the list grows.
6. **Should we change `defaults_pseudo_CT.m`'s hardcoded `'127.0.0.1'`?** No — that's a separate concern. The local pipeline ALREADY runs `mri_normalize` locally when `HOSTNAME=127.0.0.1`, so the diff between local and launchpad reflects a real architectural difference (local FreeSurfer vs. cluster FreeSurfer), not a configuration mistake. This may itself be a root-cause hint.
7. **Should we surface the comparison as an automated CI step?** Out of scope for the diagnosis change. The diff script can be run manually; wiring it into `.github/workflows/ci.yml` is a follow-up.
8. **What about the DICOM mu-map re-encoding? Is the user OK with tolerance-based comparison for those?** Assumed yes — the user explicitly mentions byte-level might be necessary for `.nii` and `.mat` but did not call out DICOM. Tolerance-based for DICOM pixel data is the only realistic option.

---

## Ready for Proposal

**Yes**, with the open questions answered as recommended.

Suggested next phases:
1. `sdd-propose` — formalize the flag + diff-script change with the recommendations above.
2. `sdd-spec` — write the deltas (one for the flag plumbing, one for the diff script API).
3. `sdd-tasks` — split into Task A (flag) and Task B (diff script), both small, single PR feasible.
4. `sdd-apply` — implement.
5. `sdd-verify` — re-run both pipelines on `test_data_*` with `keep_tmp=1` and confirm the diff script identifies the first divergent file.

The "first divergent file" diagnostic is **not** in scope of the implementation change — it is the human-driven investigation that the change UNLOCKS. The change is the *tooling* to make the investigation possible without further code edits.
