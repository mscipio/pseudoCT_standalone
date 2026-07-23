# Proposal: Unified Entrypoint Migration

## Intent

Consolidate two near-identical entrypoints (`run_pseudo_CT_local.m`, `run_pseudo_CT_launchpad.m`) into one unified `run_pseudo_CT.m` with a named-arg CLI interface and profile-selector GUI. Expose the orphan `local-near-parity-r2010b` profile. Eliminate ~70 lines of copy-pasted helper code.

## Scope

### In Scope
- New `run_pseudo_CT.m` with `inputParser` named-arg interface supporting 3 profiles
- Profile selector GUI (`src/ui/pseudo_CT_profile_selector.m`)
- Extract `collect_jobs`/`build_jobs_from_subject_list` to `src/core/`
- Move old entrypoints to `deprecated/` as-is
- R2010b warning (warn+continue, not hard error)
- Update smoke tests, run_tests, diff_entrypoint_runs, docs

### Out of Scope
- Full unification of local-vs-launchpad execution paths (sync vs batch+poll are genuinely different)
- Changes to pipeline internals (atlas, normalization, cleanup)
- Removal of old entrypoints (keep in `deprecated/` for reference)

## Capabilities

> Contract between proposal and specs phases.

### New Capabilities
- `unified-entrypoint`: named-arg CLI interface (`run_pseudo_CT('profile',NAME,'subjects',LIST)`) + profile-selector GUI + 3-profile dispatch + R2010b warn-and-continue

### Modified Capabilities
- `entrypoint-divergence-diagnostics`: cleanup-gating requirements reference `run_pseudo_CT_local.m`/`run_pseudo_CT_launchpad.m` — update to reference new `run_pseudo_CT.m`

## Approach

**Shared Helpers + Entrypoint as Coordinator.** Extract duplicated collect/helpers to `src/core/`. New `run_pseudo_CT.m` parses named args via `inputParser`. No args → profile selector GUI → `load_mr_4_AC` (file GUI). When `local-near-parity-r2010b` on wrong MATLAB → warn and patch `manifest.runtime_guard` before preflight (3-line bypass). Dispatch local-sync or launchpad-batch via switch/case. Move old entrypoints to `deprecated/` unmodified.

Key decisions: (1) `inputParser` over manual parsing for correctness; (2) manifest patching preserves canonical guard; (3) `deprecated/` excluded from MATLAB path — old callers add it manually.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `run_pseudo_CT_local.m` | Moved | → `deprecated/run_pseudo_CT_local.m` |
| `run_pseudo_CT_launchpad.m` | Moved | → `deprecated/run_pseudo_CT_launchpad.m` |
| `run_pseudo_CT.m` | Created | New primary entrypoint |
| `src/core/collect_jobs.m` | Created | Shared helper |
| `src/core/build_jobs_from_subject_list.m` | Created | Shared helper |
| `src/ui/pseudo_CT_profile_selector.m` | Created | Profile selection GUI |
| `scripts/run_smoke_tests.m` | Modified | References old entrypoints (line 27) |
| `scripts/run_tests.m` | Modified | References `run_pseudo_CT_local` (line 21) |
| `scripts/diff_entrypoint_runs.m` | Modified | References old entrypoints |
| `AGENTS.md`, `README.md` | Modified | Update entrypoint docs |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Scripts calling old entrypoints break | High | Document breaking change; `deprecated/` preserves them |
| Deployed `isdeployed` path mis-handled | Medium | Single-arg `.mat` path handled before named parsing |
| R2010b guard bypass wrong | Low | 3-line manifest patch; preflight unchanged |
| Smoke tests miss new entrypoint | Low | All 3 scripts updated in scope |

## Rollback Plan

Restore old entrypoints from `deprecated/` to root. Delete `run_pseudo_CT.m` and `src/core/`/`src/ui/` additions. Smoke tests revert with the doc changes.

## Dependencies

- Change 1 complete (`profile-resource-authority`): profiles, preflight, registry exist as foundation
- `openspec/specs/entrypoint-divergence-diagnostics` (needs delta update)

## Success Criteria

- [ ] `run_pseudo_CT('profile','local-current','subjects','batch')` matches old `run_pseudo_CT_local('batch')`
- [ ] `run_pseudo_CT()` opens profile selector then `load_mr_4_AC`
- [ ] `local-near-parity-r2010b` warns on non-R2010b but continues
- [ ] Old entrypoints live in `deprecated/` unmodified
- [ ] Smoke tests pass and verify new entrypoint parses
- [ ] Profile selector Cancel returns gracefully
