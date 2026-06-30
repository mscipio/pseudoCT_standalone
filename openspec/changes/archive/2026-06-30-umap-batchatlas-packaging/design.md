# Design: Softer UMAP Autodetection, Configurable Batch_atlas Resolution, Tagged Release Packaging

## Technical Approach

Three independent changes under one slug: (1) unify UTE/UMAP discovery into a shared `dir()`-based helper for both batch and GUI; (2) resolve `Batch_atlas/` path via env var → config default → repo-adjacent fallback; (3) extract version to `version.txt` and add `make package` for runtime-only deployment. No algorithmic changes to the atlas pipeline.

## Architecture Decisions

| Decision | Choice | Rejected | Rationale |
|---|---|---|---|
| Discovery helper location | New `src/ui/pseudo_CT_discover_ute_umap.m` | Modify batch helper in-place; keep GUI inline | Both callers need identical results per spec. Single source of truth. |
| Sibling folder scan | `dir(parent)` + `regexpi(name, pattern)` + `dir(folder/*0001*)` | `ls('*UMAP*')` wildcard (current) | `dir()` returns empty struct safely on all platforms; `ls()` crashes on Linux with no match |
| Atlas path resolution | `PSEUDOCT_BATCH_ATLAS` env → `defaults_pseudo_CT('batch_atlas_path')` → `../Batch_atlas` fallback | Config file, CLI flag | Env vars match existing operator workflow; `eval`-based defaults are the project convention |
| Version source of truth | `version.txt` (plain text, single line) | Hardcoded `code_version` string (current) | Simplest; readable by MATLAB (`fopen`/`fgetl`) and Makefile (`$(shell cat)`) |
| GUI message type | `fprintf` to stdout (shared helper) | Keep `warndlg` for GUI path | Specs mandate stdout; GUI callers adapt return values to UI fields; no modal spam |

## Discovery Algorithm Detail

**UTE search**: scan sibling folders under `MR/` parent → match `ute` (case-insensitive via `regexpi`) → validate `*0001*` content → first match or 0.

**UMAP search**: same scan → match `umap|ute|mu_map|mumap` → validate `*0001*` content → first alphabetically-sorted match or 0.

Both return `0` (numeric) on no-match — never error. Ambiguity messages print to stdout: candidate count, selected file path, containing folder.

## Atlas Path Resolution Flow

```
pseudo_CT_resolve_batch_atlas_path(repo_root)
  ├─► 1. getenv('PSEUDOCT_BATCH_ATLAS') — if set and exists, return
  ├─► 2. defaults_pseudo_CT('batch_atlas_path') — if non-empty and exists, return
  ├─► 3. fullfile(repo_root, 'Batch_atlas') — if exists, return
  └─► error('Batch_atlas not found. Checked: ...') — list all locations
```

Added to MATLAB path before SPM batch operations (the existing `addpath` pattern).

## File Changes

| File | Action | Description |
|---|---|---|
| `src/ui/pseudo_CT_discover_ute_umap.m` | **Create** | Shared `dir()`-based helper; case-insensitive sibling scan; `*0001*` content validation |
| `src/config/pseudo_CT_resolve_batch_atlas_path.m` | **Create** | Resolution function: env → default → fallback; validates existence |
| `version.txt` | **Create** | Single line: `2.6.0` |
| `src/ui/pseudo_CT_auto_discover_ute_umap.m` | Modify | Replace body with delegation to shared helper; keep existing signature |
| `src/ui/load_mr_4_AC.m` | Modify | Replace `load_automatic_ute_umap` subfunction with delegation; fix `P`→`fn` bug (line 159) |
| `src/config/defaults_pseudo_CT.m` | Modify | Add `batch_atlas_path = ''` default |
| `run_pseudo_CT_local.m` | Modify | Replace `fullfile(pathp, 'Batch_atlas')` with resolver call |
| `run_pseudo_CT_launchpad.m` | Modify | Use shared discovery helper (already calls `pseudo_CT_auto_discover_ute_umap`) |
| `src/core/atlas_based_attenuation_map.m` | Modify | Read version from `version.txt`; update `autom_select_folder` fallback to use resolver |
| `Makefile` | Modify | Read version from `version.txt` for `tag`; add `package` target |
| `scripts/run_smoke_tests.m` | Modify | Accept configurable atlas path; add parse check for new files |

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Smoke | New files parse | `mlint` on both new `.m` files in `run_smoke_tests.m` |
| Smoke | Atlas resolution with env var | `setenv('PSEUDOCT_BATCH_ATLAS', '/tmp/fake');` verify descriptive error |
| Unit | Discovery: no-match, single, multi | Temp directories with realistic layouts; assert return values and messages (extend `test_auto_discover_messages.m` pattern) |
| Integration | Pipeline output identical | Run one subject `run_pseudo_CT_local` before/after; diff `att_map.nii` |
| E2E | `make package` validity | Verify contents, run smoke tests from package root |

## Migration / Rollout

No migration required. Existing subject layouts (`MR/UMAP/`, `MR/UTE_2/`) work unchanged — the new helper is a superset of old behavior. `Batch_atlas/` must be provisioned at the configured path before running.

**Rollback**: `git revert`; restore hardcoded version and relative atlas paths. No data migration to unwind.

## Risks / Mitigations

| Risk | Probability | Mitigation |
|---|---|---|
| GUI `load_mr_4_AC.m` regression (GUIDE-generated) | Medium | Only replace the discovery subfunction; keep all GUIDE boilerplate untouched |
| `regexpi` unavailable in R2010b | Low | Introduced R2006a; confirmed compatible |
| `version.txt` not found at runtime | Low | Resolve relative to `mfilename('fullpath')` parent chain; fallback to hardcoded `'2.6.0'` |

## Open Questions

None — all spec questions were clarified before design.
