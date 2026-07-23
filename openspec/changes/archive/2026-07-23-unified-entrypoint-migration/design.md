# Design: Unified Entrypoint Migration

## Technical Approach

Create `run_pseudo_CT.m` as a coordinator that parses named args via `inputParser`, resolves profile + subjects, dispatches to local-sync or launchpad-batch execution, and reports results. Extract the two copy-pasted subfunctions (`collect_jobs`, `build_jobs_from_subject_list`) to `src/core/`. Move old entrypoints to `deprecated/` unmodified. The entrypoint owns the R2010b manifest bypass before preflight — no changes to the preflight contract.

## Architecture Decisions

### Decision: Command dispatch

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Full unification with strategy pattern | Eliminates ALL duplication but the sync vs batch+poll execution models are genuinely different; abstraction may regress | **Rejected** — not worth risk |
| Thin wrapper delegating to old entrypoints | Zero behavioral risk but doesn't fix the 70-line copy-paste | **Rejected** — misses cleanup opportunity |
| Shared helpers + switch/case dispatch | Extracts what is identical, preserves what is different; 80% reduction in duplicated code without abstraction risk | **Accepted** |

### Decision: R2010b guard bypass

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Patch `manifest.runtime_guard` before preflight | 3-line change; preflight unchanged; entrypoint owns the relaxation policy | **Accepted** |
| Add `warn_only` flag to preflight | Intrusive; changes preflight contract needed by other callers | **Rejected** |
| Change profile's runtime_guard to `supported_matlab` | Loses hard-error for direct registry callers | **Rejected** |

### Decision: Profile selector GUI

| Option | Tradeoff | Decision |
|--------|----------|----------|
| `listdlg` with descriptions in 2nd column | Works on all supported MATLAB (R2010b+); simple and proven | **Accepted** |
| Custom `uifigure` dialog | Richer UX but breaks on R2010b (no uifigure); more maintenance | **Rejected** |

### Decision: Arg parsing

| Option | Tradeoff | Decision |
|--------|----------|----------|
| `inputParser` | Standard MATLAB since R2007a; self-validating; clean error messages | **Accepted** |
| Manual `varargin` switch/case | Works but no validation; worse DX | **Rejected** |

### Decision: Deployed mode entry

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Check `isdeployed && nargin==1` before named parsing | Interprets single arg as `.mat` path, same as old launchpad behavior | **Accepted** |
| Force named args even in deployed mode | Would break existing deployed callers | **Rejected** |

## Execution Flow

```
run_pseudo_CT(varargin)
│
├── [isdeployed && nargin==1]
│   └── load(varargin{1})          # Deployed: load defaults .mat
│
├── Parse named args (inputParser)
│   profile='', subjects='', correct_aliasing=[]
│
├── [if no profile given]
│   │  profile = pseudo_CT_profile_selector()
│   │  if empty → return (cancelled)
│   │
├── [if no subjects given]
│   │  [mprage, ute, umap, alias] = load_mr_4_AC('mMR')
│   │  if mprage==0 → return
│   │
├── Resolve + patch manifest:
│   │  manifest = pseudo_CT_resolve_profile(profile, pathp)
│   │  [if near-parity + wrong MATLAB] → warn + patch runtime_guard
│   │  manifest = pseudo_CT_preflight(manifest, pathp)
│   │
├── setup_pseudo_CT_paths(pathp, manifest)
├── dir_batch_templates = pseudo_CT_resolve_batch_atlas_path(...)
│
├── jobs = collect_jobs(manifest, ...)   # shared helper
│   [if empty → return]
│
├── switch profile
│   ├── local-current / local-near-parity-r2010b:
│   │   for each job → local_run_subject(job, ...)
│   │
│   └── launchpad:
│       for each job → convert_dicom + batch_submit
│       poll all jobs
│       for each successful → finalize (mask, DICOM, promote, cleanup)
│
└── Summary dialog (single-subject) / console (batch)
```

## Data Flow

```
User input ──→ inputParser ──→ profile name ──→ pseudo_CT_resolve_profile ──→ manifest struct
                     │                               (profile_registry)
                     └── subjects ──→ collect_jobs ──→ job[] structs
                                       (shared helper)

job[] ──→ switch(profile)
           ├── local-current:        for each job → atlas_based_attenuation_map
           ├── local-near-parity:    same as local but with runtime_guard bypass
           └── launchpad:            batch_pseudo_CT_launchpad(job[], ...)

manifest ──→ pseudo_CT_preflight ──→ validated manifest
    │
    └── runtime_guard = 'r2010b_only' + wrong version → entrypoint patches BEFORE preflight
```

## Interfaces / Contracts

```matlab
% run_pseudo_CT.m — primary entrypoint
function run_pseudo_CT(varargin)
% Named parameters (inputParser):
%   'profile'          - '' (GUI), 'local-current', 'local-near-parity-r2010b', 'launchpad'
%   'subjects'         - '' (GUI), 'batch', cell/char list of MPRAGE paths
%   'correct_aliasing' - [] (manifest default), 0, 1
% Deployed mode: run_pseudo_CT('defaults.mat') loads from argument

% src/core/collect_jobs.m
function jobs = collect_jobs(manifest, varargin)
% Input:  manifest struct, varargin (subject list or 'batch')
% Output: struct array with fields: mprage_fn, umap_fn, correct_aliasing
%         Empty if no subjects or GUI cancelled

% src/core/build_jobs_from_subject_list.m
function jobs = build_jobs_from_subject_list(subject_list, correct_aliasing)
% Input:  char matrix of MPRAGE paths, scalar correct_aliasing
% Output: struct array with fields: mprage_fn, umap_fn, correct_aliasing
% Note:   Same as local_build_jobs/launchpad_build_jobs (100% identical)

% src/ui/pseudo_CT_profile_selector.m
function profile = pseudo_CT_profile_selector()
% Output: 'local-current', 'local-near-parity-r2010b', 'launchpad', or '' (cancelled)
% Side effects: listdlg dialog; warndlg if near-parity on non-R2010b
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Invalid profile name | Error listing valid profiles ('local-current', 'local-near-parity-r2010b', 'launchpad') |
| Empty job list | Warning restore + return (same as current behavior) |
| UMAP missing | Subject included in job list but downstream skip (unchanged, in build_jobs) |
| Preflight failure | Error from pseudo_CT_preflight (unchanged) |
| R2010b on wrong MATLAB | warn + patch manifest.runtime_guard → continue (non-blocking) |
| GUI cancel | Graceful return, no processing |

## File Changes

| File | Action | Description |
|------|--------|------------|
| `run_pseudo_CT.m` | Create | Unified primary entrypoint with `inputParser` named args |
| `src/core/collect_jobs.m` | Create | Shared helper extracted from local/launchpad subfunctions |
| `src/core/build_jobs_from_subject_list.m` | Create | Shared builder extracted from local/launchpad subfunctions |
| `src/ui/pseudo_CT_profile_selector.m` | Create | Profile selection dialog via `listdlg` |
| `run_pseudo_CT_local.m` | Move | → `deprecated/run_pseudo_CT_local.m` |
| `run_pseudo_CT_launchpad.m` | Move | → `deprecated/run_pseudo_CT_launchpad.m` |
| `scripts/run_smoke_tests.m` | Modify | Check `run_pseudo_CT.m` + `deprecated/` files |
| `scripts/run_tests.m` | Modify | Update entrypoint reference |
| `scripts/diff_entrypoint_runs.m` | Modify | Update doc references |
| `AGENTS.md` | Modify | Document `run_pseudo_CT.m` as primary entrypoint |
| `README.md` | Modify | Document unified entrypoint + deprecated/ |

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | `inputParser` arg validation | Test valid/invalid profiles, empty subjects, deployed mode `.mat` arg |
| Unit | `collect_jobs.m` | Empty manifest → empty output; valid manifest → jobs; varargin dispatch |
| Unit | `build_jobs_from_subject_list.m` | Subject list → jobs; subject w/o UMAP → skipped |
| Unit | `pseudo_CT_profile_selector.m` | Each selection returns correct string; Cancel returns `''` |
| Integration | `run_pseudo_CT('profile','local-current','subjects',{'batch'})` | Smoke test parses; dispatches to local-sync path |
| Integration | R2010b warning on non-R2010b | Manifest patched, warning issued, execution continues |
| Integration | Launchpad dispatch | `run_pseudo_CT('profile','launchpad')` calls `batch_pseudo_CT_launchpad` |
| Regression | Old entrypoints from `deprecated/` | `addpath deprecated/; run_pseudo_CT_local('batch')` works as before |
| Smoke | `scripts/run_smoke_tests.m` | All checks pass; `run_pseudo_CT.m` parses; `deprecated/` files exist |

## Threat Matrix

**N/A** — this change does not touch routing, shell commands, subprocesses, VCS/PR automation, executable-file classification, or process-integration boundaries. The existing FreeSurfer SSH subprocess path is unchanged (it lives inside `atlas_based_attenuation_map.m` and `batch_pseudo_CT_launchpad.m`, which are not modified).

## Migration / Rollout

**Breaking change**: Old entrypoints move to `deprecated/`. Direct callers break. Documented migration path: add `addpath('deprecated/')` or update script to call `run_pseudo_CT.m` with named args.

Rollback: Restore old entrypoints from `deprecated/` to root. Delete `run_pseudo_CT.m`, `src/core/collect_jobs.m`, `src/core/build_jobs_from_subject_list.m`, `src/ui/pseudo_CT_profile_selector.m`.

## Open Questions

- [ ] None — all decisions resolved by proposal and specs.
