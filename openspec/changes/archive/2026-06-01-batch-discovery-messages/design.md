# Design: Batch-Mode Auto-Discovery Messages

## Technical Approach

Add unconditional `fprintf(1, ...)` calls inside `pseudo_CT_auto_discover_ute_umap.m` at the five branch points where discovery fails or is ambiguous. The function already receives `mprage_fn` regardless of invocation mode — no mode-switching or `nargin` logic is needed. Messages are harmless in interactive mode (GUI users rarely see the console) and critical in batch mode (operators need subject-level traceability). No caller changes, no return-value changes, no new files.

The five insertion points map directly to the spec's six scenarios (the "UMAP via wildcard success" scenario is the default silent path, requiring no message):

| Line | Condition | Message |
|------|-----------|---------|
| 9 | `ss` empty | MR parent path not found |
| 12 | `listi` empty | No UTE found |
| 15 | `listi` > 1 | Multiple UTE candidates, chosen file |
| 19-24 | Primary UMAP empty → wildcard also empty | No UMAP found |
| 23 | `listi` > 1 (primary) | Multiple UMAP candidates, chosen |
| 33 | `listi` > 1 (wildcard) | Multiple UMAP candidates (wildcard), chosen |

## Architecture Decisions

| Decision | Options | Tradeoffs | Choice |
|----------|---------|-----------|--------|
| Output mechanism | `warning()` vs `fprintf(1, ...)` vs `disp()` | `warning()`: suppressed by `warning('off','all')` at entry points (lines 62/64). `fprintf(1,...)`: explicit stdout, survives suppression, format-friendly. `disp()`: also survives, but less idiomatic for formatted output | `fprintf(1, ...)` — survives global suppression, matches spec requirement |
| Message scope | Callee (`pseudo_CT_auto_discover_ute_umap.m`) vs callers (`run_pseudo_CT_local.m` / `run_pseudo_CT_launchpad.m`) | Callee: one change site, free observability for all callers. Callers: duplicates across two entry points, would miss any third-party callers | Callee — single point of change, zero caller modifications |
| Conditional vs unconditional | Guard on `nargin` or a new `verbose` param vs always emit | Mode detection: adds parameter complexity, the function always receives `mprage_fn` regardless of mode. Unconditional: trivial diff, messages are low-noise in interactive mode (GUI users don't look at console) | Unconditional — zero control-flow risk, simplest possible change |

## Data Flow

```
run_pseudo_CT_local/launchpad
  │  warning('off','all') active
  │
  └── pseudo_CT_auto_discover_ute_umap(mprage_fn)
        │
        ├── No MR/ parent ──▶ fprintf('WARNING: No MR/ parent ...') ──▶ [0, 0]
        │
        ├── No UTE found ──▶ fprintf('WARNING: No UTE found ...') ──▶ [0, *]
        ├── Multiple UTE   ──▶ fprintf('WARNING: Multiple UTE ...')  ──▶ [first, *]
        │
        ├── No UMAP ─────────▶ fprintf('WARNING: No UMAP found ...') ──▶ [*, 0]
        ├── Multiple UMAP     ──▶ fprintf('WARNING: Multiple UMAP ...')                                        2′⟶ [*, first]

Messages flow to stdout (fprintf fid=1), bypassing warning suppression.
Callers then check `umap_fn` and `disp()` their existing skip message as before.
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `src/ui/pseudo_CT_auto_discover_ute_umap.m` | Modify | Insert `fprintf(1, ...)` at 5 branch points; no other lines changed |

No new files. No caller modifications. No delete operations.

## Interfaces / Contracts

No new interfaces. The function signature remains:

```matlab
function [ute_fn, umap_fn] = pseudo_CT_auto_discover_ute_umap(mprage_fn)
```

Return-value contract is preserved: `ute_fn=0` when no UTE found, `umap_fn=0` when no UMAP found, first candidate path string otherwise. All existing callers in `run_pseudo_CT_local.m:174` and `run_pseudo_CT_launchpad.m:238` continue to work unchanged.

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Manual smoke | Batch run on a directory with subjects covering: no UMAP, multiple UMAPs, no UTE, no MR parent | Run `run_pseudo_CT_local('batch')` against a test subject set; verify console output contains expected messages with subject paths, verify no subject that should be skipped is erroneously processed |
| Contract | Return values unchanged | Compare `ute_fn`/`umap_fn` output before and after the change for each scenario |

No automated test framework exists in this repo. Verification is manual: run the pipeline and inspect console output. This matches the project's existing testing posture.

## Migration / Rollout

No migration required. The change is additive: `fprintf` lines only, no control-flow or return-value changes.

**Rollback**: `git revert` — the diff adds lines only; reverting removes them and restores original silence.

**Rollout**: Apply the change, run a batch test against a mixed subject set (subjects with and without UMAP). Confirm console shows expected messages for missing/ambiguous cases and no messages for successful discovery. No feature flags or phased deployment needed.

## Open Questions

None.
