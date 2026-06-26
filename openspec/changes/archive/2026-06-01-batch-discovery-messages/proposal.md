# Proposal: Batch-Mode Auto-Discovery Messages

## Intent

`pseudo_CT_auto_discover_ute_umap.m` silently returns `0` for missing or ambiguous UTE/UMAP discovery. In batch mode, operators cannot tell which subjects were skipped or why. Both entry points (`run_pseudo_CT_local.m:62`, `run_pseudo_CT_launchpad.m:64`) call `warning('off','all')`, so `warning()` calls are invisible — only `disp`/`fprintf` reach the console.

## Scope

### In Scope
- Add explicit `fprintf` messages to `pseudo_CT_auto_discover_ute_umap.m` for: no UTE found, multiple UTE candidates, no UMAP found, multiple UMAP candidates, no `MR/` parent path detected
- Messages must identify the subject path so batch logs are traceable
- Use `fprintf(1, ...)` (stdout) — not `warning()` — to survive global warning suppression

### Out of Scope
- Changing any return values or control flow
- Adding messages to interactive/GUI mode
- Modifying callers or other source files
- Adding logging infrastructure beyond console output

## Capabilities

### New Capabilities
- `batch-autodiscovery-observability`: Console coverage for missing and ambiguous auto-discovery outcomes in batch mode, making silent skips visible in run logs.

### Modified Capabilities
None.

## Approach

Add conditional `fprintf` calls at each branch where discovery fails or is ambiguous inside `pseudo_CT_auto_discover_ute_umap.m`. Detect batch mode via `nargin < 1` isn't applicable (function always receives `mprage_fn`), so emit messages unconditionally — they are harmless in interactive mode and essential in batch. Each message includes the subject path for traceability.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/ui/pseudo_CT_auto_discover_ute_umap.m` | Modified | Add `fprintf` calls at 5 branch points |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Console noise in interactive mode | Low | `disp`/`fprintf` to stdout is harmless; GUI users rarely see console |
| Mistaken for breaking change | Low | No return-value or control-flow change; pure addition |

## Rollback Plan

`git revert` — the change adds lines only, no refactoring. Removing the added `fprintf` lines restores original silence.

## Dependencies

None.

## Success Criteria

- [ ] Batch-mode run on a subject with missing UMAP prints a clear message naming the subject and what was not found
- [ ] Batch-mode run on a subject with multiple UMAP candidates prints an ambiguity warning naming the chosen file
- [ ] Return values (`ute_fn`, `umap_fn`) are unchanged for all cases