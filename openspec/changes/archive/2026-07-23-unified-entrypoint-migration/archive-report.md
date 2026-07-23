# Archive Report: unified-entrypoint-migration

**Archived**: 2026-07-23
**Previous location**: `openspec/changes/unified-entrypoint-migration/`
**Archive path**: `openspec/changes/archive/2026-07-23-unified-entrypoint-migration/`

## Change Summary

Consolidated two near-identical entrypoints (`run_pseudo_CT_local.m`, `run_pseudo_CT_launchpad.m`) into one unified `run_pseudo_CT.m` with a named-arg CLI interface (`inputParser`) and profile-selector GUI. Exposed the orphan `local-near-parity-r2010b` profile. Extracted duplicated helper functions (`collect_jobs`, `build_jobs_from_subject_list`) to `src/core/` as shared code. Moved old entrypoints to `deprecated/` unmodified. Updated smoke tests, run_tests, and documentation.

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 — Foundation | Shared helpers: `collect_jobs.m`, `build_jobs_from_subject_list.m`, `pseudo_CT_profile_selector.m` | ✅ Complete |
| 2 — Core | New `run_pseudo_CT.m` entrypoint with 3-profile dispatch | ✅ Complete |
| 3 — Migration | Old entrypoints → `deprecated/`, scripts updated | ✅ Complete |
| 4 — Documentation | AGENTS.md, README.md, CHANGELOG.md updated | ✅ Complete |

## Verification Status

- **Tests**: 115 passed, 0 failed, 1 skipped (Batch_atlas absent — expected)
- **Spec compliance**: Verified
- **Design compliance**: Verified
- **CRITICAL issues**: None
- **Warnings addressed**: Yes

## Task Completion

All 12 implementation tasks across 4 phases completed. Persisted tasks artifact in Engram (#716) shows unchecked checkboxes due to `sdd-apply` not marking them in the persisted observation. **Exceptional reconciliation performed**: apply-progress (#717) and verify-report (#718) prove all tasks complete per orchestrator instruction.

### Tasks by Phase

- 1.1 Create `src/core/build_jobs_from_subject_list.m` ✅
- 1.2 Create `src/core/collect_jobs.m` ✅
- 1.3 Create `src/ui/pseudo_CT_profile_selector.m` ✅
- 2.1 Create `run_pseudo_CT.m` — unified entrypoint ✅
- 3.1 Move old entrypoints to `deprecated/` ✅
- 3.2 Update `scripts/run_smoke_tests.m` ✅
- 3.3 Update `scripts/run_tests.m` ✅
- 3.4 Update `scripts/run_lint.m` ✅
- 3.5 Update `scripts/test_alias_runtime.m` + `test_profile_env_resistance.m` ✅
- 4.1 Update `AGENTS.md` ✅
- 4.2 Update `README.md` ✅
- 4.3 Update `CHANGELOG.md` ✅

## Spec Sync

No delta spec files existed in the change folder (spec was persisted only in Engram). The unified-entrypoint-migration change creates new code artifacts rather than modifying existing specs. Proposal noted an optional delta to `openspec/specs/entrypoint-divergence-diagnostics` but this was not in scope for the change.

## Archive Contents

- proposal.md ✅
- design.md ✅
- archive-report.md ✅

## Engram Observation IDs

| Topic | ID |
|-------|----|
| `sdd/unified-entrypoint-migration/explore-v2` | #712 |
| `sdd/unified-entrypoint-migration/proposal` | #713 |
| `sdd/unified-entrypoint-migration/spec` | #714 |
| `sdd/unified-entrypoint-migration/design` | #715 |
| `sdd/unified-entrypoint-migration/tasks` | #716 |
| `sdd/unified-entrypoint-migration/apply-progress` | #717 |
| `sdd/unified-entrypoint-migration/verify-report` | #718 |

## Source of Truth Updated

No main specs were modified by this change (code-only change — entrypoint consolidation does not alter spec domains).

## Intentional Archive Notes

- **Stale-checkbox reconciliation**: Tasks artifact (#716) had unchecked checkboxes despite all tasks being complete. Reconciled based on explicit user confirmation that all 4 phases were implemented and verification passed with 115 tests. Apply-progress (#717) and verify-report (#718) corroborate completion.
- **Missing OpenSpec artifacts**: No `specs/`, `tasks.md`, or `verify-report.md` existed on the filesystem for this change (Engram-only persistence was used for those phases). Archive is intentional-with-warnings — all core artifacts (proposal, design) are present.
- **No review gate**: Project does not use the SDD review pipeline. Archive proceeds on orchestrator instruction.

## SDD Cycle Complete

The change has been fully planned, implemented, verified, and archived.
Ready for the next change.
