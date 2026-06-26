# Tasks: Batch-Mode Auto-Discovery Messages

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~20–30 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Add `fprintf` observability at 5 discovery branch points | PR 1 | Base = main; single file, additive only |

## Phase 1: Core Implementation

- [x] 1.1 `src/ui/pseudo_CT_auto_discover_ute_umap.m` — add `else` after line 9 `if length(ss) > 0` with `fprintf(1, 'WARNING: No MR/ parent in %s\n', patha)` for the no-MR-parent case
- [x] 1.2 `src/ui/pseudo_CT_auto_discover_ute_umap.m` — after line 12 `listi` empty (no UTE), add `fprintf(1, 'WARNING: No UTE found in %sUTE_2/\n', dir_b)`
- [x] 1.3 `src/ui/pseudo_CT_auto_discover_ute_umap.m` — after line 16 `listi > 1` (multiple UTE), add `fprintf(1, 'WARNING: %d UTE candidates in %s, using %s\n', ...)` identifying ambiguity and chosen file
- [x] 1.4 `src/ui/pseudo_CT_auto_discover_ute_umap.m` — after line 30 (wildcard dir scan also empty), add `fprintf(1, 'WARNING: No UMAP found in %s\n', dir_b)`
- [x] 1.5 `src/ui/pseudo_CT_auto_discover_ute_umap.m` — after line 23 (multiple UMAP in `UMAP/`), add `fprintf(1, 'WARNING: %d UMAP candidates in %sUMAP/, using %s\n', ...)`
- [x] 1.6 `src/ui/pseudo_CT_auto_discover_ute_umap.m` — after line 34 (multiple UMAP via wildcard), add `fprintf(1, 'WARNING: %d UMAP candidates in %s, using %s\n', ...)` with wildcard path

## Phase 2: Verification

- [ ] 2.1 Manual smoke test — run `run_pseudo_CT_local('batch')` against a subject set covering all 6 spec scenarios; confirm each `fprintf` message appears on stdout with subject path
- [ ] 2.2 Contract check — verify `ute_fn`/`umap_fn` return values match pre-change behavior for missing (0), single (path string), and multiple (first path) cases
- [ ] 2.3 Visual diff inspection — confirm the only changes are additive `fprintf` calls; no control flow, return values, or indentation changes

## Phase 3: Cleanup

- [ ] 3.1 Rollback test — `git diff` to confirm a clean revert would restore original silence (additive-only change)
