# Proposal: Softer UMAP Autodetection, Configurable Batch_atlas Resolution, Tagged Release Packaging

## Intent

Three problems block standalone distribution: (1) UMAP autodetection crashes on Linux (`ls('*UMAP*')` with no match) and is case-sensitive; (2) `Batch_atlas/` (gitignored, 735 MB) is found via three hardcoded relative paths; (3) version is hardcoded in one `.m` file, the Makefile tag target is broken, and no packaging script exists.

## Scope

### In Scope
- Unify batch + GUI UMAP autodiscovery into a shared helper: `dir()`-based, case-insensitive, `exist`-guarded
- Config-driven `batch_atlas_path` default + `PSEUDOCT_BATCH_ATLAS` env-var fallback; plumb into `atlas_based_attenuation_map` and `move_image_2_MNI`
- Single `version.txt`; Makefile `git tag` + `package` target for runtime-only deployable folder
- Update smoke tests for configured atlas path

### Out of Scope
- Launchpad backend atlas config; CI licensing fix; test framework; GUI figure redesign

## Capabilities

### New Capabilities
- `ute-umap-discovery`: Shared case-insensitive UTE/UMAP autodiscovery helper replacing two divergent implementations
- `batch-atlas-resolution`: Configurable `Batch_atlas` location via default + env var + relative fallback
- `release-packaging`: Single version source, automated tagging, runtime-only folder assembly

### Modified Capabilities
- `batch-autodiscovery-observability`: Scenarios must account for case-insensitive matching and unified helper paths

## Approach

Unify both discovery functions into `src/ui/pseudo_CT_discover_ute_umap.m` via `dir()` + `regexp`. Add `batch_atlas_path` to `defaults_pseudo_CT.m` with env fallback. Move `code_version` to `version.txt`; Makefile reads it for tagging and builds a folder excluding non-runtime dirs.

## Affected Areas

- **New**: `src/ui/pseudo_CT_discover_ute_umap.m`, `version.txt`
- **Modified — delegate to helper**: `pseudo_CT_auto_discover_ute_umap.m`, `load_mr_4_AC.m`
- **Modified — atlas path default**: `defaults_pseudo_CT.m`
- **Modified — atlas override, version read**: `run_pseudo_CT_local.m`, `_launchpad.m`
- **Modified — receive atlas path**: `atlas_based_attenuation_map.m`, `move_image_2_MNI.m`
- **Modified — version + package**: `Makefile`
- **Modified — accept configured atlas path**: `run_smoke_tests.m`

## Risks

- **GUIDE breakage in `load_mr_4_AC.m`** (Medium): minimal wiring; verify figure loads
- **R2010b incompatibility** (Medium): `regexp`/`dir` only; smoke parse check

## Rollback Plan

`git revert`; remove `version.txt`; restore hardcoded version and relative atlas paths.

## Dependencies

MATLAB R2010b+ (unchanged); `Batch_atlas/` provided at configured/env path.

## Success Criteria

- [ ] `dir()`-based discovery never crashes on Linux with no match
- [ ] `Batch_atlas` found via env var without repo-root assumption
- [ ] `make package` produces a runtime-only folder with correct version tag
- [ ] Pipeline output identical to pre-change for a test subject

## Proposal question round

Orchestrator captured direction (A1/B3/C1/D2). Remaining:

1. **Match scope**: Any folder containing `umap`/`ute`/`mu_map` (case-insensitive), or only known variants?
2. **Package contents**: Include 735 MB `Batch_atlas/` in the archive, or operator places it post-extract?
3. **GUI risk**: Edit GUIDE-generated `load_mr_4_AC.m` now, or defer (batch-only first)?

Assumptions: env-var fallback desired; `version.txt` plain-text single-line; package excludes non-runtime dirs.
