# Design: MATLAB Version E2E Compatibility

## Technical Approach

A single non-interactive Bash script (`run_matlab_version_e2e.sh`) sequentially sweeps five MATLAB versions × two PCA modes using the local pipeline entry point. Before each run, it safely copies the subject input-data folder into a version×mode-tagged output tree. After all runs complete (or skip with cause), it invokes the MATLAB report aggregator to produce `compatibility.md`. Resumability via state file, failure isolation per run, timestamped per-run logs. No existing source, CI, or changelog files are modified.

## Architecture Decisions

| Option | Tradeoff | Decision |
|--------|----------|----------|
| State-file resumability vs marker files | Marker files per run: fragile naming. State file: atomic, grep-able | JSON-lines state file (`OUT_ROOT/.e2e_state`); each line = `VERSION MODE STATUS TIMESTAMP` |
| `cp -a` vs `rsync -a` for input copy | `cp` is universal but no incremental resume. `rsync` handles partial copies but not guaranteed on all nodes | `cp -a` with explicit directory existence check; if destination exists and state shows prior failure, `rm -rf` before re-copy |
| `set -e` (fail-fast) vs per-run error capture | `set -e` kills the sweep on first MATLAB crash — unacceptable for multi-hour job | Per-run wrapping: capture exit code, log to per-run file, never abort the sweep. `set +e` for the runner |
| Report invocation: inline vs post-sweep | Inline: partial matrix on crash. Post-sweep: clean artifact, resumability | Post-sweep only — after all runs complete/skip, invoke `run_matlab_version_e2e_report.m` once |
| MATLAB version discovery: inferred from executable names vs runner-owned explicit mapping | Inferring from `command -v matlab*` patterns is fragile across clusters and does not distinguish pre-/post-R2023b naming conventions. Explicit mapping: single source of truth, versionable, auditable | **Runner-owned `RELEASE_TO_VERSION` associative array** encoding the authoritative R2010a–R2026a mapping (32 entries). Binary discovery: on-disk check `[ -x /usr/pubsw/bin/matlab$ver ]` where `$ver` is the mapped numeric string. Missing → SKIP. |
| Input: single DICOM path vs data folder | Single DICOM couples to subject tree discovery. Folder: self-contained, safe to copy | `INPUT_DATA_DIR` — the subject root containing `MR/MEMPRAGE/`, `MR/UMAP/`; the runner resolves the MPRAGE `.dcm` path internally |

## Data Flow

```
Operator: INPUT_DATA_DIR=/data/subj1 OUT_ROOT=/tmp/e2e ./scripts/run_matlab_version_e2e.sh [--resume|--force]

 ┌── run_matlab_version_e2e.sh ──────────────────────────────────┐
 │ 1. Validate INPUT_DATA_DIR and Launchpad ref                   │
 │ 2. Read/init .e2e_state (JSON-lines)                            │
 │ 3. For each VERSION × PCA_MODE:                                │
 │    ├─ Skip if state says DONE & --force not set                │
 │    ├─ Look up RELEASE_TO_VERSION[$VERSION] → numeric ver str    │
 │    ├─ [ -x /usr/pubsw/bin/matlab$ver ] → available; else SKIP   │
 │    ├─ mkdir -p <OUT_ROOT>/matlab_<V>_<M>                       │
 │    ├─ Write state: V M RUNNING <ts>                            │
 │    ├─ cp -a $INPUT_DATA_DIR → <OUT_ROOT>/matlab_<V>_<M>/data/  │
 │    ├─ /usr/pubsw/bin/matlab$ver -nosplash -nodisplay -r "..."  │
 │    │    > <OUT_ROOT>/log/matlab_<V>_<M>.log 2>&1              │
 │    ├─ Capture exit code → DONE|FAILED <ts>                     │
 │    └─ Continue (NEVER abort loop)                              │
 │ 4. After loop: invoke run_matlab_version_e2e_report.m          │
 │ 5. Write sweep summary to stdout and OUT_ROOT/sweep_summary.txt│
 └───────────────────────────────────────────────────────────────┘

 ┌── run_matlab_version_e2e_report.m ────────────────────────────┐
 │ Walk OUT_ROOT/matlab_*/MR_PET/tmp/                             │
 │ Per V×M: diff_entrypoint_runs(local, launchpad, 'OutputCSV',…) │
 │ Classify: IDENTICAL|VOXEL_DIVERGENT|HEADER_ONLY|EXPECTED|SKIP  │
 │ Emit compatibility.md (2 tables × ~15 stages × 5 versions)     │
 └───────────────────────────────────────────────────────────────┘
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `scripts/run_matlab_version_e2e.sh` | Create | Unattended Bash runner: state-file resumability, safe copy, per-run logging, failure isolation, post-sweep report invocation |
| `scripts/run_matlab_version_e2e_report.m` | Create | MATLAB aggregator: walks per-version trees, calls `diff_entrypoint_runs`, emits `compatibility.md` |
| `docs/matlab-version-compat-E2E.md` | Create | Operator procedure: prerequisites, input-data layout contract, invocation, log interpretation |

## Interfaces / Contracts

**RELEASE_TO_VERSION mapping** — runner-owned, embedded in `run_matlab_version_e2e.sh`:

```bash
declare -A RELEASE_TO_VERSION=(
  [R2010a]=7.10   [R2010b]=7.11   [R2011a]=7.12   [R2011b]=7.13
  [R2012a]=7.14   [R2012b]=8.0    [R2013a]=8.1    [R2013b]=8.2
  [R2014a]=8.3    [R2014b]=8.4    [R2015a]=8.5    [R2015b]=8.6
  [R2016a]=9.0    [R2016b]=9.1    [R2017a]=9.2    [R2017b]=9.3
  [R2018a]=9.4    [R2018b]=9.5    [R2019a]=9.6    [R2019b]=9.7
  [R2020a]=9.8    [R2020b]=9.9    [R2021a]=9.10   [R2021b]=9.11
  [R2022a]=9.12   [R2022b]=9.13   [R2023a]=9.14   [R2023b]=23.2
  [R2024a]=24.1   [R2024b]=24.2   [R2025a]=25.1   [R2025b]=25.2
  [R2026a]=26.1
)
# Pre-R2023b: major.minor (e.g. R2018b → 9.5)
# R2023b+: year-based XX.1=a, XX.2=b (e.g. R2024b → 24.2)
MATLAB_BIN_DIR="/usr/pubsw/bin"
SWEEP_VERSIONS="R2010b R2013b R2018b R2022b R2026a"
```

**Binary discovery** — per release in sweep:
```bash
matlab_ver="${RELEASE_TO_VERSION[$release]}"
matlab_bin="${MATLAB_BIN_DIR}/matlab${matlab_ver}"
if [ ! -x "$matlab_bin" ]; then
    log_skip "$release $mode" "binary not found: $matlab_bin"
    continue  # SKIP cell, never substitute, never abort
fi
```

**Shell runner** — non-interactive, headless:
```bash
INPUT_DATA_DIR=/data/subject_root          # must contain MR/MEMPRAGE/ and MR/UMAP/
LAUNCHPAD_REF=/autofs/.../test_data_launchpad
OUT_ROOT=/tmp/e2e_$(date +%Y%m%d_%H%M)

./scripts/run_matlab_version_e2e.sh              # fresh sweep
./scripts/run_matlab_version_e2e.sh --resume     # skip completed runs
./scripts/run_matlab_version_e2e.sh --force      # re-run all, ignoring state
```
Environment overrides: `SWEEP_VERSIONS`, `PCA_MODES`, `LAUNCHPAD_REF`, `MATLAB_BIN_DIR`.

**State file** (`OUT_ROOT/.e2e_state`):
```
R2010b native    DONE    2026-07-13T08:14:22
R2010b legacy    DONE    2026-07-13T09:31:05
R2013b native    SKIP    2026-07-13T09:31:05   binary not found: /usr/pubsw/bin/matlab8.2
R2018b native    FAILED  2026-07-13T10:45:12   exit=1
```

**Report** (`run_matlab_version_e2e_report.m`):
```matlab
run_matlab_version_e2e_report(out_root, launchpad_ref_dir)
% Reads .e2e_state to discover completed trees
% Calls diff_entrypoint_runs per V×M; emits compatibility.md
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Smoke | Report `.m` parses | `run_smoke_tests.m` auto-includes new scripts in parse glob |
| Unit | State-file read/write correctness | Bash unit: `source scripts/run_matlab_version_e2e.sh; test_state_transitions` |
| Unit | RELEASE_TO_VERSION mapping completeness | Verify all 32 entries present; verify R2023b+ follows year-based convention (≥23.x) |
| Unit | Input-data copy integrity | `cp -a` followed by `diff -rq` on source vs copied tree |
| E2E | Full sweep produces `compatibility.md` | Operator runs unattended; verifies matrix, state file, per-run logs |
| E2E | Resumability | Interrupt mid-sweep, re-run `--resume`; only incomplete runs execute |
| E2E | Failure isolation | Simulate MATLAB crash on one version; confirms script continues |
| E2E | Missing-binary skip | Run with a SWEEP_VERSIONS that includes a version not on disk; confirms SKIP not abort |
| Audit | No source files modified | `git diff --name-only` confirms only `scripts/` and `docs/` |

## Threat Matrix

Shell subprocess + filesystem-write boundary:

| Boundary | Applicability | Design response | Planned RED tests |
|----------|--------------|-----------------|-------------------|
| Documentation-like paths | Applicable | `INPUT_DATA_DIR` validated as existing directory; `OUT_ROOT` created or rejected if non-empty without `--force`; MATLAB binary validated via explicit `[ -x ]` check against the RELEASE_TO_VERSION mapping before invocation; mapping is the sole authority — no executable-name inference | Non-existent INPUT_DATA_DIR → exit 1 with message; non-allowlist version → SKIP not invoked; missing binary → SKIP with logged path |
| Git/commit/push/PR rows | N/A | No git commands, no commits, no PR automation | None |
| Filesystem-write (safe copy) | Applicable | `cp -a` with explicit pre-checks; `rm -rf` only inside OUT_ROOT versioned subdirectories; no wildcard deletion above OUT_ROOT | Attempt to write above OUT_ROOT → rejected |

## Migration / Rollout

No migration required. Artifacts purely additive. Removal deletes `scripts/run_matlab_version_e2e.sh`, `scripts/run_matlab_version_e2e_report.m`, `docs/matlab-version-compat-E2E.md`, plus any generated output trees.

## Open Questions

- [ ] **docs/ folder acceptability** — confirm with investigation-cleanup-release agent no conflict with release packaging
- [ ] **Timeout per MATLAB run** — pipeline takes ~2h per subject. Should the runner impose a wall-clock timeout (e.g., 4h) to prevent hangs in unattended mode?
