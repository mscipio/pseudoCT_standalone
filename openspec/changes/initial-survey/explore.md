# Exploration: Initial Survey

## Current State

The pseudo-CT package is a MATLAB/SPM8 pipeline with two entry points (`run_pseudo_CT_local.m`, `run_pseudo_CT_launchpad.m`). Two changes were archived on 2026-06-01:

1. **`batch-discovery-messages`** — Added `fprintf` observability to `pseudo_CT_auto_discover_ute_umap.m` for missing/ambiguous UTE/UMAP discovery. The delta spec lives on as the active main spec at `openspec/specs/batch-autodiscovery-observability/spec.md`. The code changes are present in `src/ui/pseudo_CT_auto_discover_ute_umap.m` (all 5 branch points emit `fprintf(1, ...)` messages).
2. **`pipeline-quality-fixes`** — Extracted `src/config/setup_pseudo_CT_paths.m`, modernized operators (`isstr`→`ischar`, `|`→`||`, `&`→`&&`), and normalized `mkdir`/`rmdir` success checks (`== 0` → `~`). All changes are present in the codebase.

There are **no active changes** under `openspec/changes/`.

## Affected Areas

- `src/ui/pseudo_CT_auto_discover_ute_umap.m` — Already contains the `batch-discovery-messages` `fprintf` additions.
- `src/config/setup_pseudo_CT_paths.m` — Created by `pipeline-quality-fixes`.
- `run_pseudo_CT_local.m` / `run_pseudo_CT_launchpad.m` — Already use bootstrap + helper pattern and modernized operators.
- `src/core/atlas_based_attenuation_map.m` — Already uses `ischar` and `||`; one mixed `&&`/`&` at L253 remains (noted in archive report, deferred).
- `src/io/convert_dicom_i_2_nii.m` — Already modernized.
- `openspec/specs/batch-autodiscovery-observability/spec.md` — Active spec with no corresponding open change.

## Approaches

### 1. Archive the active spec as a completed change
- **Description**: Create a lightweight archive entry for `batch-autodiscovery-observability` noting it was implemented and bundled into `pipeline-quality-fixes` commit `ed94bbb`.
- **Pros**: Closes the spec loop; avoids confusion about why an active spec has no open change.
- **Cons**: Slightly redundant since the archive report for `pipeline-quality-fixes` already mentions the bundled observability messages.
- **Effort**: Low

### 2. Leave the active spec in place and start a new change
- **Description**: Treat the current state as the new baseline. Propose the next functional improvement (e.g., wiring `test_auto_discover_messages.m` into CI, fixing the remaining `&`→`&&` at L253, or adding a formal test framework).
- **Pros**: Moves the project forward; the spec is already implemented so no delta work is needed.
- **Cons**: The active spec may appear orphaned if not explicitly closed.
- **Effort**: Medium (depends on chosen next change)

## Recommendation

**Approach 2** — The active spec is fully realized in code. Rather than spending cycles archiving a spec that is already live, the next productive step is to propose a new change. Two good candidates:

- **Fix the deferred `&`→`&&` at `atlas_based_attenuation_map.m:253`** (tiny, low-risk, closes a known lint warning).
- **Wire `scripts/test_auto_discover_messages.m` into CI** (adds real test coverage to the existing GitHub Actions workflow; currently it only runs manually).

## Risks

- **Archived scope overlap**: The `batch-discovery-messages` change was archived with unchecked verification tasks (manual smoke test, contract check, rollback test). The archive report for `pipeline-quality-fixes` states these were verified by `git diff` inspection, but no runtime test was executed. Risk is low because the changes are purely additive `fprintf` calls with no control-flow changes.
- **AGENTS.md ↔ scripts consistency**: Verified consistent. Smoke test assertions match repo contents (7 DARTEL templates present, ganymed JAR present at expected path, all parse checks aligned).
- **Code-version drift**: `code_version = '2.5'` in `atlas_based_attenuation_map.m:90` matches the version history written to `Pseudo_CT_AC_Version.txt`. No drift.
- **Stale skill registry**: `.atl/skill-registry.md` references `/homes/7/mu512/` paths. Should be refreshed with `gentle-ai skill-registry refresh --force` before any subagent delegations that rely on skill loading.
- **Mixed `&&`/`&` at L253**: A latent lint warning in `atlas_based_attenuation_map.m`. Not critical, but should be cleaned up in the next quality pass.

## Ready for Proposal

**Yes**. The active spec (`batch-autodiscovery-observability`) is fully implemented. There are no blockers. The orchestrator should ask the user which next change to pursue:
1. A tiny operator fix (`&`→`&&` at L253), or
2. CI integration of the existing TDD test script (`test_auto_discover_messages.m`).
