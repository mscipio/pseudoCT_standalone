# Design: Entrypoint Divergence Diagnosis

## Technical Approach

Two-phase change: (A) config/env-driven temp preservation gates at three cleanup sites, (B) a MATLAB comparator script that dispatches on file type by extension and reports first divergence. Default behavior stays cleanup-on-success unless `keep_temp_files = 'Yes'` in defaults or `PSEUDOCT_KEEP_TMP=1` in environment. Follows the project's existing env-var override pattern (`PSEUDOCT_BATCH_ATLAS`) and name-value arg plumbing (`batch_pseudo_CT_launchpad`'s `clean_folder`/`check_aliasing`).

## Architecture Decisions

### Decision: Keep-temp resolution chain

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Env var only | Simple, no file edits, but not persistent | Not sufficient — user wants config activation |
| Defaults field only | Persistent, but requires file edit to toggle | Not sufficient — env override faster for one-off runs |
| Both: defaults as base, env overrides | Persistence + quick toggle; matches `PSEUDOCT_BATCH_ATLAS` precedent | ✅ Chosen |

**Resolution**: `getenv('PSEUDOCT_KEEP_TMP')` → truthy (`'1'`/`'true'`/`'yes'` case-insensitive) → `'Yes'`. Else `defaults_pseudo_CT[_launchpad]('keep_temp_files')`. Shared via `src/config/pseudo_CT_keep_temp_enabled.m(defaults_handle)`. Truthy check uses `strcmpi` (R2010b-compatible, no `contains`/`startsWith`).

### Decision: `pseudo_CT_cleanup_intermediates` handling

**Choice**: Leave dormant. Already gated by `clean_folder=0` in the launchpad entry. `keep_temp_files` adds a separate layer for `rmdir`/`rm -rf` blocks only. No scope entanglement.

### Decision: Diff comparator dispatch

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| NIfTI (`.nii`) | `spm_read_vols`, max abs diff vs tolerance | SPM8 already on path; handles scaling |
| DICOM (`.dcm`) | `dicomread` + header diff; binary fallback if Image Toolbox absent | May not be installed; degrade gracefully |
| MATLAB (`.mat`) | `load` + `isequal` / MD5 fallback | SPM batch files; byte-exact expected |
| Text (`.txt`/`.log`/`.sh`) | MD5 | Simple, unambiguous |
| Other | Binary compare | Catch-all |
| Known diff list | Hardcoded struct: `Pseudo_CT_AC_Version.txt` (version string), `Fusion_MR_Pseudo_CT_validation.tiff` (local-only QC) | Easy to edit; no sidecar config needed |
| Report | Console table + optional CSV | Human-readable; scriptable |

### Decision: `cd` neutrality

The comparator does NOT `cd` — `diff_entrypoint_runs(local_dir, launchpad_dir)` uses `fullfile` for all path construction. Entry scripts already manipulate `cd`; comparator must be side-effect-free.

## Data Flow

```
  defaults_pseudo_CT[_launchpad].m        PSEUDOCT_KEEP_TMP env
         │                                       │
         └───────┬───────────────────────────────┘
                 ▼
    pseudo_CT_keep_temp_enabled(defaults_handle)
                 │
        ┌────────┼────────┐
        ▼        ▼        ▼
  run_local  run_lp   batch_lp (keep_tmp arg)
  rmdir gate rmdir    cluster rm -rf gate
```

```
  diff_entrypoint_runs(local_dir, lp_dir)
         │
    dir() both ──► intersect filenames (sorted)
         │
    per-file dispatch:
      .nii  → spm_read_vols + max(|diff|) vs tol
      .dcm  → dicomread + header (binary fallback)
      .mat  → load + isequal / MD5
      text  → MD5
      other → binary compare
         │
    report: IDENTICAL | DIVERGENT | EXPECTED_DIFF |
            LOCAL_ONLY | LAUNCHPAD_ONLY
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `src/config/defaults_pseudo_CT.m` | Modify | Add `keep_temp_files = 'No'` after L16 |
| `src/config/defaults_pseudo_CT_launchpad.m` | Modify | Add `keep_temp_files = 'No'` after L23 |
| `src/config/pseudo_CT_keep_temp_enabled.m` | **Create** | Env+defaults resolution helper; returns `'Yes'`/`'No'` |
| `run_pseudo_CT_local.m` | Modify | L234: replace `button='Yes'` with keep-temp check; gate L238-239 rmdir |
| `run_pseudo_CT_launchpad.m` | Modify | L114: add `'keep_tmp',1/0` to batch call; L118: gate rmdir |
| `src/launchpad/batch_pseudo_CT_launchpad.m` | Modify | L6: add `keep_tmp=0` default; L23-31: add case; L129: gate `rm -rf` |
| `scripts/diff_entrypoint_runs.m` | **Create** | MATLAB comparator (~150 lines) |

## Interfaces / Contracts

```matlab
% Keep-temp resolution — called from both entry scripts
function out = pseudo_CT_keep_temp_enabled(defaults_handle)
%   DEFAULTS_HANDLE: e.g. @defaults_pseudo_CT or @defaults_pseudo_CT_launchpad
%   Returns 'Yes' or 'No'

% Comparator entry point
function diff_entrypoint_runs(local_dir, launchpad_dir, varargin)
%   Name-value args: 'Tolerance', 1e-6, 'OutputCSV', ''
%   Prints structured report to console; optionally writes CSV

% batch_pseudo_CT_launchpad new arg (existing name-value pattern)
%   'keep_tmp' — numeric 0|1, default 0. When 1, skips cluster-side rm -rf.
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Smoke | New files exist and parse | Extend `scripts/run_smoke_tests.m` with new `.m` file checks |
| Lint | Modified files pass mlint | `scripts/run_lint.m` already covers `src/`, entry scripts, `vers/` |
| Manual | Temp preservation | Run both entrypoints with `PSEUDOCT_KEEP_TMP=1` on test_data; verify `MR_PET/tmp/` survives |
| Manual | Comparator correctness | `diff_entrypoint_runs` on preserved runs; verify IDENTICAL `MPRAGE_spm.nii`, DIVERGENT `MPRAGE_spm_normalized.nii` |
| Manual | Default production behavior | Run without env var; verify `MR_PET/tmp/` deleted as before |

## Risks

| Risk | Mitigation |
|------|-----------|
| `dicomread` absent → DICOM compare degrades to binary-only | Graceful fallback with warning; binary diff still catches meaningful divergence |
| Compiled v2.0 binary writes fewer files → LOCAL_ONLY noise | Known-diff list filters `Fusion_MR_Pseudo_CT_validation.tiff`; remaining LOCAL_ONLY files are investigation data |
| `MR_PET/tmp/` fills disk if operator forgets to disable | `keep_temp_files` defaults to `'No'`; env var is session-scoped |
| Review budget: ~200 changed lines (modifications) + ~200 new (comparator) | Under 400-line threshold; single PR feasible |

## Open Questions

- [ ] Is `dicomread` (Image Processing Toolbox) available on the user's MATLAB? If absent, DICOM comparison falls back to binary-only with a warning.
- [ ] Should `Pseudo_CT_AC_Version.txt` be EXPECTED_DIFF (exists in both, content differs) or LOCAL_ONLY? Spec says EXPECTED_DIFF for known-diff files — this is correct since the file exists in both trees but the compiled binary writes a different version string.
