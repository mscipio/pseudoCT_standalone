# Tasks: Softer UMAP Autodetection, Configurable Batch_atlas Resolution, Tagged Release Packaging

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 200–250 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | UTE/UMAP discovery + atlas resolution + packaging | PR 1 (single) | All units independent, total < 400 lines |

## Phase 1: Foundation

- [x] 1.1 Create `src/ui/pseudo_CT_discover_ute_umap.m` — `dir()`-based sibling scan with `regexpi` matching `umap|ute|mu_map|mumap`, `*0001*` content validation, returns `0` on no-match, stdout messages for missing/ambiguous results
- [x] 1.2 Create `src/config/pseudo_CT_resolve_batch_atlas_path.m` — resolve via `PSEUDOCT_BATCH_ATLAS` env → `defaults_pseudo_CT('batch_atlas_path')` → repo-adjacent fallback; descriptive error listing all checked locations
- [x] 1.3 Create `version.txt` — single plain-text line: `2.6.0`

## Phase 2: Core Wiring

- [x] 2.1 Delegate `pseudo_CT_auto_discover_ute_umap.m` body to shared helper from 1.1; keep exact call signature
- [x] 2.2 Replace `load_automatic_ute_umap` subfunction in `load_mr_4_AC.m` with shared helper call; fix `P`→`fn` bug at line 159
- [x] 2.3 Add `batch_atlas_path = ''` default to `defaults_pseudo_CT.m`
- [x] 2.4 Replace `fullfile(pathp, 'Batch_atlas')` in `run_pseudo_CT_local.m` with resolver from 1.2; pass resolved path to `local_run_subject`
- [x] 2.5 Wire `version.txt` read + resolver fallback in `atlas_based_attenuation_map.m`; replace hardcoded `code_version = '2.5'` and repo-relative `Batch_atlas` fallback

## Phase 3: Release Packaging

- [x] 3.1 Update `Makefile` — `tag` target reads version from `version.txt` via `$(shell cat)`; add `package` target that builds release folder excluding `.git/`, `scripts/test_*`, `.github/`, `openspec/`, `Batch_atlas/`

## Phase 4: Testing

- [x] 4.1 Update `scripts/test_auto_discover_messages.m` for shared helper (new file, unified behavior, updated message format)
- [x] 4.2 Update `scripts/run_smoke_tests.m` — accept configurable atlas path via env var; add `mlint` checks for both new `.m` files
