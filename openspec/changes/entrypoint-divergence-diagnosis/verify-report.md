## Verification Report

**Change**: entrypoint-divergence-diagnosis
**Spec domain**: entrypoint-divergence-diagnostics
**Version**: N/A (spec has no version field)
**Mode**: Standard (Strict TDD disabled — no formal MATLAB test framework in this project)
**Date**: 2026-07-08
**Verifier**: sdd-verify sub-agent
**MATLAB**: R2026a Update 2 (26.1.0.3251617) 64-bit (glnxa64)

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 22 |
| Tasks complete (automated) | 19 |
| Tasks incomplete (manual end-to-end) | 3 (4.3, 4.4, 4.5) |
| Implementation/core tasks | all complete |
| Cleanup/manual-verification tasks | 3 remaining (require real MRI data + cluster SSH) |

### Build & Tests Execution

**Build (MATLAB parse)**: Passed — all new and modified files load and run under MATLAB R2026a.

**Smoke tests**: 90 passed / 0 failed / 1 skipped
```text
Command: matlab -nodesktop -nosplash -nodisplay -r "run('scripts/run_smoke_tests.m')"
Result:  === Results: 90 passed, 0 failed, 1 skipped ===
Skip:    Batch_atlas assets absent (expected in this checkout)
```

Behavioral tests added by this change (all PASS at runtime):
- `pseudo_CT_keep_temp_enabled` env/defaults precedence — 6/6 pass
  (PSEUDOCT_KEEP_TMP=1→Yes, =true→Yes, =0→No, unset→No, broken handle→No, =Yes→Yes)
- `diff_entrypoint_runs` text pipeline — 4/4 pass via CSV verification
  (identical.txt→IDENTICAL, divergent.txt→DIVERGENT, local_only.log→LOCAL_ONLY, lp_only.log→LAUNCHPAD_ONLY) + CSV file produced
- `compare_hash_strings` sentinel guard — 6/6 pass
  (READ_ERROR+READ_ERROR→DIVERGENT, READ_ERROR+MD5_UNAVAILABLE→DIVERGENT, READ_ERROR+valid→DIVERGENT, valid+MD5_UNAVAILABLE→DIVERGENT, identical valid→IDENTICAL, different valid→DIVERGENT)
- DICOM dispatch (extension + magic-byte) — 2/2 pass
  (.ima extension→DICOM comparison, extensionless+DICM magic→DICOM comparison)

**Lint**: New files clean; modified files pre-existing issues only
```text
Command: mlint per-file
New files (0 issues each):
  src/config/pseudo_CT_keep_temp_enabled.m   : 0
  scripts/compare_hash_strings.m             : 0
  scripts/diff_entrypoint_runs.m             : 0
Modified files (pre-existing legacy style only — disp(sprintf)→fprintf, mlint→checkcode):
  run_pseudo_CT_local.m                      : 13 (pre-existing)
  run_pseudo_CT_launchpad.m                  : 15 (pre-existing)
  src/launchpad/batch_pseudo_CT_launchpad.m  : 10 (pre-existing)
  src/config/defaults_pseudo_CT.m            :  8 (pre-existing)
  src/config/defaults_pseudo_CT_launchpad.m  : 13 (pre-existing)
```
No new lint issues introduced on changed lines. The single added line in each defaults file is a plain assignment; the `should_cleanup` rename and `fprintf(1,[...])` keep-tmp message in `batch_pseudo_CT_launchpad.m` are lint-clean.

**Coverage**: Not available — project has no coverage tool (strict_tdd=false, no MOxUnit/matlab.unittest).

### Spec Compliance Matrix

| Requirement | Scenario | Test / Evidence | Result |
|-------------|----------|-----------------|--------|
| Temp Preservation Config | Enabling via defaults | Source: `run_pseudo_CT_local.m` gates `rmdir` on `should_cleanup`; helper precedence 6/6 pass | ✅ COMPLIANT (logic + helper runtime; pipeline runtime pending 4.3) |
| Temp Preservation Config | Default production behavior unchanged | Source: defaults `'No'` + env unset → `should_cleanup=true` → rmdir executes | ✅ COMPLIANT (source; pipeline runtime pending 4.5) |
| Cleanup Gating — Local Entry | Local rmdir suppressed | Source: `elseif should_cleanup` gate; helper returns 'Yes' when enabled | ✅ COMPLIANT (source + helper runtime; pipeline runtime pending 4.3) |
| Cleanup Gating — Launchpad Entry | Launchpad dual cleanup suppressed | Source: `'keep_tmp',keep_tmp_val` passed to batch + local rmdir gated | ✅ COMPLIANT (source; pipeline runtime pending 4.3) |
| Cluster-Side Cleanup Gate | Cluster scratch preserved | Source: `batch_pseudo_CT_launchpad.m` `if keep_tmp==0 ... else print preserved path` | ✅ COMPLIANT (source; cluster runtime pending — requires Launchpad SSH) |
| Entrypoint Diff Comparator | Identical and divergent NIfTI files | Source: `compare_nifti` spm_read_vols + max abs diff + detail; text-pipeline dispatch 4/4 pass | ⚠️ PARTIAL — dispatch+report framework runtime-tested; NIfTI pixel path source-inspected only (requires real .nii + SPM vol) |
| Entrypoint Diff Comparator | Expected difference suppressed | Source: `KNOWN_EXPECTED_DIFF={'Pseudo_CT_AC_Version.txt'}` checked before dispatch | ✅ COMPLIANT (source; trivial branch in tested dispatch flow) |
| Entrypoint Diff Comparator | File present in one tree only | Runtime: `local_only.log`→LOCAL_ONLY, `lp_only.log`→LAUNCHPAD_ONLY via CSV | ✅ COMPLIANT |
| Comparison Semantics | Tolerance absorbs float rounding | Source: `compare_nifti` `if max_diff <= tol → IDENTICAL`, tol=1e-6 configurable | ⚠️ PARTIAL — source-inspected; no runtime NIfTI test (requires real .nii) |
| Comparison Semantics | Byte-level mismatch detected | Runtime: `compare_hash_strings` 6/6 pass; `compare_mat` load+isequal→MD5 fallback | ✅ COMPLIANT |

**Compliance summary**: 8/10 scenarios COMPLIANT, 2/10 PARTIAL (NIfTI pixel path source-inspected, not runtime-tested with real volumes — requires SPM + real NIfTI test fixtures which are not available as synthetic data).

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|------------|--------|-------|
| `keep_temp_files='No'` in both defaults | ✅ Implemented | `defaults_pseudo_CT.m` L17, `defaults_pseudo_CT_launchpad.m` L24 |
| `PSEUDOCT_KEEP_TMP` env override | ✅ Implemented | `pseudo_CT_keep_temp_enabled.m`: env first (1/true/yes case-insensitive via strcmpi), then defaults, then 'No' on error. R2010b-safe. |
| Local final cleanup gate | ✅ Implemented | `run_pseudo_CT_local.m`: `should_cleanup` boolean gates `rmdir(temp_working_dir,'s')` |
| Launchpad final cleanup gate | ✅ Implemented | `run_pseudo_CT_launchpad.m`: `should_cleanup` gates local rmdir; `keep_tmp_val` passed to batch |
| Cluster-side `rm -rf` gate | ✅ Implemented | `batch_pseudo_CT_launchpad.m`: `keep_tmp` name-value arg; `if keep_tmp==0` gates ssh2 rm; else prints preserved path + cleanup command |
| NIfTI tolerance compare | ✅ Implemented | `compare_nifti`: spm_read_vols, size check, max abs diff vs tol (default 1e-6) |
| MAT/hash compare | ✅ Implemented | `compare_mat`: load+isequal, MD5 fallback; `compare_hash_strings` sentinel-safe (READ_ERROR/MD5_UNAVAILABLE never → IDENTICAL) |
| DICOM robust dispatch | ✅ Implemented | Known extensions (.dcm/.ima/.dicom/.dic) + magic-byte DICM at offset 128 (`is_dicom_file`); header (dicominfo, 12 fields) + pixel (dicomread) with degraded-mode reporting |
| Known expected differences | ✅ Implemented | `Pseudo_CT_AC_Version.txt`→EXPECTED_DIFF, `Fusion_MR_Pseudo_CT_validation.tiff`→LOCAL_ONLY |
| Report output (console + CSV) | ✅ Implemented | Console table + summary + first-divergent highlight; optional CSV via 'OutputCSV' |
| `cd` neutrality | ✅ Implemented | All paths via `fullfile`; no `cd` in comparator |
| `pseudo_CT_cleanup_intermediates` untouched | ✅ Verified | Not modified (design decision honored) |

### Coherence (Design)

| Decision | Followed? | Notes |
|----------|-----------|-------|
| Keep-temp resolution: env → defaults (both, not one) | ✅ Yes | Matches `PSEUDOCT_BATCH_ATLAS` precedent; strcmpi for R2010b compat |
| `pseudo_CT_cleanup_intermediates` left dormant | ✅ Yes | Not touched; `keep_temp_files` is a separate layer for rmdir/rm-rf only |
| Comparator dispatch by extension + type | ✅ Yes | NIfTI/DICOM/MAT/text/binary; DICOM extended with magic-byte (documented alignment) |
| Known diff list hardcoded | ✅ Yes | No sidecar config; easy to edit |
| Report: console table + optional CSV | ✅ Yes | |
| `cd` neutrality | ✅ Yes | fullfile only |

### Issues Found

**CRITICAL**: None.

**WARNING**:
1. **3 manual end-to-end tasks incomplete (4.3, 4.4, 4.5)** — require running both entrypoints on real test data with `PSEUDOCT_KEEP_TMP=1`, then `diff_entrypoint_runs` on preserved intermediates, then without env var to confirm default cleanup. These are explicitly designated Manual in the design testing strategy and the spec Non-Goals state "Does NOT require CI to run full clinical datasets." They require: real MPRAGE DICOMs, FreeSurfer 5.3, SPM8 segmentation/DARTEL, and (for Launchpad) cluster SSH access to the compiled `Pseudo_CT_launchpad` binary. Automated behavioral coverage of the gates and comparator is strong (90/90 smoke pass), but the end-to-end pipeline-level preservation and NIfTI divergence detection are not yet runtime-proven on real data.
2. **NIfTI pixel-compare path not runtime-tested** — `compare_nifti` (spm_read_vols + max abs diff) is source-inspected and follows the tested dispatch framework, but no synthetic NIfTI fixture exercises the pixel-diff branch at runtime. Synthetic NIfTI creation requires SPM volume-writing machinery not available in a lightweight test. The spec scenario "Identical and divergent NIfTI files" and "Tolerance absorbs float rounding" are therefore PARTIAL.

**SUGGESTION**:
1. **DICOM empty-pixel detail string** — when `dicomread` returns empty arrays (e.g., synthetic/minimal DICOM files with no real pixel data), `max_diff` is `[]` (size [0 1]); `if [] <= tol` evaluates to false → DIVERGENT (safe direction), but `sprintf('%g', [])` produces an empty string, yielding an uninformative detail like `"DICOM header match, pixel diff = "`. This is cosmetic — the STATUS is conservatively correct — but the detail is not actionable. Recommend guarding: if `isempty(max_diff)`, report `"pixel data empty on one or both sides"` in the detail. Does not affect real scanner DICOMs (which have pixel data).
2. **CSV detail field unescaped commas** — `write_csv` writes `results(f).detail` directly; detail strings containing commas (e.g., `"DICOM header mismatch: PatientName: differ; ...; ...;"`) would break CSV parsing. Low risk for the current detail strings, but recommend quoting or replacing commas in the detail column if CSV consumers are added later.

### Remaining Manual Verification (operator, with two datasets)

Both test-data directories exist and contain `MR/` + `MR_PET/` subtrees:
- `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/test_data_local`
- `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/test_data_launchpad`

| # | Task | Command sketch | Expected |
|---|------|----------------|----------|
| 4.3 | Temp preservation ON | `PSEUDOCT_KEEP_TMP=1` → run `run_pseudo_CT_local` and `run_pseudo_CT_launchpad` on test data | `MR_PET/tmp/` survives after success; cluster scratch preserved (Launchpad prints preserved path) |
| 4.4 | Comparator on real runs | `diff_entrypoint_runs(<local_tmp>, <launchpad_tmp>, 'OutputCSV','report.csv')` | `MPRAGE_spm.nii`→IDENTICAL; `MPRAGE_spm_normalized.nii`→DIVERGENT with max pixel diff; `Pseudo_CT_AC_Version.txt`→EXPECTED_DIFF; QC TIFF→LOCAL_ONLY |
| 4.5 | Default cleanup unchanged | unset `PSEUDOCT_KEEP_TMP` → run both entrypoints | `MR_PET/tmp/` removed as before (production behavior preserved) |

### Verdict

**PASS WITH WARNINGS**

All automated implementation tasks (19/19) are complete; all executable behavioral tests pass at runtime (90 smoke tests, 0 fail — including 18 new behavioral assertions covering keep-temp precedence, comparator dispatch, MD5 sentinel guard, and DICOM magic-byte routing); all 3 new files lint clean (0 issues); spec scenarios with available test fixtures are COMPLIANT. The 2 PARTIAL scenarios (NIfTI pixel path) and 3 incomplete manual end-to-end tasks (4.3/4.4/4.5) are explicitly designated Manual in the design and require real MRI data + FreeSurfer + cluster SSH — they do not block the automated-implementation verdict but must be executed by the operator before archiving the change as fully production-verified.
