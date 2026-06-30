# Archive Report: umap-batchatlas-packaging

**Archived**: 2026-06-30
**Previous location**: `openspec/changes/umap-batchatlas-packaging/`
**Archive path**: `openspec/changes/archive/2026-06-30-umap-batchatlas-packaging/`

## Change Summary

Combined change covering three deployability concerns:
1. **UTE/UMAP discovery**: Unified case-insensitive `dir()`-based shared helper replacing two divergent implementations
2. **Batch_atlas resolution**: Configurable atlas path via env var → config default → relative fallback
3. **Release packaging**: Single `version.txt` source, `make tag`/`make package` targets

## Verification Status

- **Final verdict**: PASS (all tests green)
- **Re-verification**: PASS after post-verify fix (UMAP multi-file-in-single-folder ambiguity)
- **Smoke tests**: 46/46 PASS
- **Auto-discover tests**: 17/17 PASS (GREEN)
- **CRITICAL issues**: None

## Task Completion

All 11 implementation tasks completed with checkboxes marked in persisted tasks artifact. One post-verify fix applied (Batch 2) addressing multi-file collapse in single-sibling-folder ambiguity detection.

## Spec Sync

| Domain | Action | Details |
|--------|--------|---------|
| `ute-umap-discovery` | Created | New main spec at `openspec/specs/ute-umap-discovery/spec.md` |
| `batch-atlas-resolution` | Created | New main spec at `openspec/specs/batch-atlas-resolution/spec.md` |
| `release-packaging` | Created | New main spec at `openspec/specs/release-packaging/spec.md` |
| `batch-autodiscovery-observability` | Updated | 3 MODIFIED requirements merged from delta: Missing UTE Notification, Missing UMAP Notification, Ambiguous UMAP Candidate Notification. 4 requirements preserved unchanged. |

## Archive Contents

- proposal.md ✅
- specs/ ✅ (4 domains)
- design.md ✅
- tasks.md ✅ (11/11 tasks complete)
- archive-report.md ✅

## Engram Observation IDs

- `sdd/umap-batchatlas-packaging/proposal` — #56
- `sdd/umap-batchatlas-packaging/spec` — #65
- `sdd/umap-batchatlas-packaging/design` — #70
- `sdd/umap-batchatlas-packaging/apply-progress` — #73
- `sdd/umap-batchatlas-packaging/verify-report` — #76 (decision observation: "Verified umap-batchatlas-packaging: PASS")

## Source of Truth Updated

The following main specs now reflect the new behavior:
- `openspec/specs/ute-umap-discovery/spec.md`
- `openspec/specs/batch-atlas-resolution/spec.md`
- `openspec/specs/release-packaging/spec.md`
- `openspec/specs/batch-autodiscovery-observability/spec.md`

## Intentional Archive Notes

None — standard clean archive. No stale-checkbox reconciliation needed.

## SDD Cycle Complete

The change has been fully planned, implemented, verified, and archived.
