# Proposal: Extract Version Changelog

## Intent

Remove the stale hardcoded version-history writer from `atlas_based_attenuation_map.m` and replace `version.txt` with one canonical `CHANGELOG.md`. Today the pipeline exports `Pseudo_CT_AC_Version.txt` from MATLAB source that ends at v2.5 while the repo is v2.6.0.

## Scope

### In Scope
- Create root `CHANGELOG.md` as the only version/history source.
- `CHANGELOG.md` line 1 MUST be the exact current version only, machine-parseable by Makefile/runtime readers.
- Remaining `CHANGELOG.md` content MUST be reverse chronological full history, including minor/patch releases, ending with the existing citation/footer content.
- Update Makefile/package/runtime version reads to use `CHANGELOG.md` line 1 and stop relying on `version.txt`.
- Replace the pipeline-end `fprintf` block with a simple local copy to `Pseudo_CT_AC_Version.txt`, with graceful fallback if `CHANGELOG.md` cannot be read.

### Out of Scope
- Rewriting release history into rich `Added/Fixed/Changed` sections.
- End-to-end pipeline behavior changes beyond the exported version log.
- Automating README changelog synchronization.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `release-packaging`: canonical release metadata moves from `version.txt` to `CHANGELOG.md` line 1; runtime packages include the changelog.

## Approach

Transcribe existing history/footer into `CHANGELOG.md`, prepend the current bare version line, and include the v2.6.0 entry from README. Update Makefile and `atlas_based_attenuation_map.m` version lookup to read line 1. Add an R2010b-safe helper or inline path using only `fopen`/`fread`/`fwrite`/`fclose`-era APIs to copy `CHANGELOG.md` to `Pseudo_CT_AC_Version.txt` at pipeline end. If the file is unavailable in deployed/unusual layouts, write a minimal fallback rather than failing the pipeline.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `CHANGELOG.md` | New | Canonical version + history/footer artifact |
| `version.txt` | Removed | Replaced by `CHANGELOG.md` line 1 |
| `Makefile` | Modified | Parse/package `CHANGELOG.md` |
| `src/core/atlas_based_attenuation_map.m` | Modified | Remove hardcoded log block; copy changelog |
| `scripts/run_smoke_tests.m` | Modified | Assert changelog exists and helper/source parses |
| `openspec/specs/release-packaging/spec.md` | Modified | Update canonical metadata contract |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| History transcription error | Med | Compare migrated output against existing block plus v2.6.0 |
| Deployed path cannot find changelog | Med | R2010b-safe lookup with graceful fallback |
| Tooling still expects `version.txt` | Med | Update Makefile/runtime/tests together |

## Rollback Plan

Restore `version.txt`, Makefile line-1 parsing, and the previous MATLAB `fprintf` block; remove `CHANGELOG.md` from packaging.

## Dependencies

- Existing `release-packaging` spec and Makefile release flow.

## Success Criteria

- [ ] `make package` derives the version from `CHANGELOG.md` line 1 and ships `CHANGELOG.md`.
- [ ] Pipeline output `Pseudo_CT_AC_Version.txt` is an exact copy of `CHANGELOG.md` on the normal path.
- [ ] Smoke tests cover changelog presence and R2010b-compatible source parsing.
