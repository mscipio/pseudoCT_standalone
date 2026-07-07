# Tasks: Extract Version Changelog

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~150 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-always |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

## Phase 1: Changelog Artifact (Foundation)

- [x] 1.1 Create `CHANGELOG.md` — line 1 = `2.6.0`, reverse-chronological history v2.6.0→v1.1, JNM citation footer
- [x] 1.2 Create `src/io/pseudo_CT_write_version_log.m` — R2010b-safe fopen/fread/fwrite/fclose copy of CHANGELOG.md; fallback writes `code_version` + `date`

## Phase 2: Core Integration

- [x] 2.1 Modify `src/core/atlas_based_attenuation_map.m` L90–104: read `CHANGELOG.md` line 1 for `code_version` instead of `version.txt`
- [x] 2.2 Modify `src/core/atlas_based_attenuation_map.m` L669–695: replace `fprintf` block with call to `pseudo_CT_write_version_log(code_version, paths)`
- [x] 2.3 Modify `Makefile` L4: `VERSION = $(shell head -n 1 CHANGELOG.md | tr -d '[:space:]')`
- [x] 2.4 Modify `Makefile` L26: `cp CHANGELOG.md` replaces `cp version.txt`
- [x] 2.5 Modify `Makefile` L32–34: remove `cp Makefile`, `cp -r scripts`, `rm -f scripts/test_auto_discover_messages.m`

## Phase 3: Verification

- [x] 3.1 Extend `run_smoke_tests.m` — assert CHANGELOG.md exists, `pseudo_CT_write_version_log.m` parses, version.txt absent
- [x] 3.2 Verified: `make package` ships CHANGELOG.md, excludes version.txt/Makefile/scripts/ (verified structurally via smoke test Makefile contract checks + prior runtime package reproduction)
- [x] 3.3 Verified: pipeline-end Pseudo_CT_AC_Version.txt matches CHANGELOG.md content (runtime evidence from verify phase: isequal=true)

## Phase 4: Cleanup

- [x] 4.1 Delete `version.txt`
- [x] 4.2 Update `openspec/specs/release-packaging/spec.md` — canonical source → CHANGELOG.md; package excludes version.txt/Makefile/scripts/
