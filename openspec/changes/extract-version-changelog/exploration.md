# Exploration: Extract Hardcoded Version-Changelog Block from atlas_based_attenuation_map.m

**Slug:** `extract-version-changelog`
**Topic key (Engram):** `sdd/extract-version-changelog/explore`
**Date:** 2026-07-07
**Status:** Exploration complete. Ready for `sdd-propose`.

## Current State

### The "changelog" in question

The last section of `src/core/atlas_based_attenuation_map.m` (lines 669-695) writes a per-subject file `Pseudo_CT_AC_Version.txt` with a hardcoded, multi-line "version history" block. The block is hand-maintained in the MATLAB source and lists 22 entries from Version 1.1 to Version 2.5, plus the JNM paper citation and an "Enjoy it" footer. It runs on every pipeline execution regardless of the actual current code version.

The relevant block:

```matlab
% Write a txt file with the code version!
fid = fopen(fullfile(paths, 'Pseudo_CT_AC_Version.txt'), 'wt');
s = sprintf('Pseudo-CT code version: %s\nDate: %s', code_version, date);
fprintf(fid, '%s', s);
fprintf(fid, '\nVersion 1.1: we fill the head with soft-tissue when no atlas is present!');
... (22 hand-written lines, ending with v2.5) ...
fprintf(fid, '\nEnjoy it ;)) !!!');
fclose(fid);
```

The file ends up in the subject's processing directory and is later promoted by `src/io/pseudo_CT_promote_final_outputs.m:20`.

### The version-release Makefile mechanism (already in place)

- `version.txt` (line 1 = `2.6.0`, line 2 = a `#`-prefixed summary) is the canonical version source.
- `Makefile:4` reads it: `VERSION = $(shell head -n 1 version.txt | tr -d '[:space:]')`.
- `Makefile:12-15` (`make tag`) creates an annotated git tag `v<VERSION>`.
- `Makefile:20-37` (`make package`) assembles `dist/pseudoCT_v<VERSION>/` and `dist/pseudoCT_v<VERSION>.tar.gz` with only runtime files.
- The runtime `atlas_based_attenuation_map.m:90-104` already reads `version.txt` at the top of the file (with a hardcoded `'2.6.0'` fallback) to populate the `code_version` variable used in the per-subject log.

### Three copies of the same content, one of them already stale

The per-version history is replicated in three places:

| Location | Last version listed | Last updated |
|---|---|---|
| `src/core/atlas_based_attenuation_map.m:670-689` (hardcoded `fprintf` block) | **2.5** (May 28, 2026) | original |
| `README.md:96-122` (Version History section) | **2.6.0** | commit `c3726eb` (Jun 30, 2026) |
| `version.txt:2` (single-line `#` comment) | **2.6.0** | commit `c3726eb` (Jun 30, 2026) |

**Drift already present:** the runtime `Pseudo_CT_AC_Version.txt` written by every local pipeline run still claims v2.5 is the latest release, even though the actual code is at v2.6.0. Adding a v2.6.1 line to the `.m` block has not happened, so every subject processed with the current `main` branch ships a stale changelog.

### What the existing main spec `release-packaging` already covers

`openspec/specs/release-packaging/spec.md` defines four requirements:
1. Single canonical version source (`version.txt`)
2. Tag consistency (tag matches `version.txt`)
3. Runtime-only package assembly
4. Versioned release layout with shared `Batch_atlas/`

**It does NOT cover the per-subject `Pseudo_CT_AC_Version.txt` content or any in-pipeline changelog generation.** That is a gap: the spec stops at "version string is consistent" but the pipeline ALSO writes a per-subject log with a long history block, and that block is the orphan in this story.

### Why the existing change `umap-batchatlas-packaging` did not catch this

The 2026-06-30 archive report for `umap-batchatlas-packaging` (and its design.md, lines 73-77) explicitly flagged "version.txt not found at runtime" as a risk and added the read from `version.txt`. It introduced `version.txt` and the Makefile targets, but it did not extract the in-source changelog block. The exploration phase of that change noted:

> **Version output**: `Pseudo_CT_AC_Version.txt` written to the processing directory at runtime (lines 666-681) with a full changelog.

…but the subsequent design treated the in-source `fprintf` block as out of scope ("No algorithmic changes to the atlas pipeline"). The block survived the change unaltered, which is why the drift was not fixed when v2.6.0 was released.

## Affected Areas

- `src/core/atlas_based_attenuation_map.m:669-695` — the hardcoded `fprintf` history block. Owner of the change; ~22 lines removed and replaced with a single helper call.
- `src/core/atlas_based_attenuation_map.m:90-104` — already reads `code_version` from `version.txt`; no change needed, but the new helper will receive it as a parameter.
- `src/io/pseudo_CT_promote_final_outputs.m:20` — promotes `Pseudo_CT_AC_Version.txt` from temp to processing dir. No change needed; same filename, same location.
- `CHANGELOG.md` (NEW, repo root) — canonical per-version history. Source for both the runtime file and the Makefile bundle. Format mirrors the current per-line entries (e.g., `- 2.6.0: unified UMAP discovery, configurable Batch_atlas resolution, and standalone release packaging.`).
- `src/io/pseudo_CT_write_version_log.m` (NEW) — helper: reads `CHANGELOG.md` from the repo root (resolved via `mfilename('fullpath')` walk-up), takes `code_version` as input, writes `Pseudo_CT_AC_Version.txt` with header + changelog + citation footer.
- `Makefile` — extend the `package` target to copy `CHANGELOG.md` into `dist/pseudoCT_v<VERSION>/`; optional `changelog` target for linting the entry count against the tag count.
- `scripts/run_smoke_tests.m` — add a parse check for the new `src/io/pseudo_CT_write_version_log.m`; assert `CHANGELOG.md` exists at the repo root.
- `README.md:96-122` — out of scope for this change. Stays as the human-facing view; drift risk between README and CHANGELOG.md is reduced from 3-way to 2-way. A future `make sync-readme` target could auto-derive the README section, but that is a documentation follow-up, not a release-blocking concern.
- `openspec/specs/release-packaging/spec.md` — may need a small MODIFIED requirement to make the per-subject `Pseudo_CT_AC_Version.txt` content scope explicit. See "Approach 3" below.

## Approaches

### 1. Canonical `CHANGELOG.md` + dedicated writer helper (Recommended)

- Move the 22 hand-written lines out of `atlas_based_attenuation_map.m` and into a top-level `CHANGELOG.md` in the same format already used by `version.txt:2` and `README.md`. One entry per release, plain text, parseable line-by-line.
- New helper `src/io/pseudo_CT_write_version_log.m` reads `CHANGELOG.md` and writes `Pseudo_CT_AC_Version.txt` with: header (version + date) → per-version lines → citation footer.
- `atlas_based_attenuation_map.m:670-695` collapses to a single call. Net code removed in `atlas_based_attenuation_map.m` is ~22 lines; net code added in `src/io/pseudo_CT_write_version_log.m` is ~30 lines (helper + parse).
- Makefile `package` target copies `CHANGELOG.md` into `dist/pseudoCT_v<VERSION>/` so the bundle carries the same canonical changelog.
- **Pros:**
  - Single canonical source for the per-version history. New release = edit `CHANGELOG.md` only.
  - Runtime file is automatically up-to-date with the current repo version.
  - Release bundle ships with the changelog next to `version.txt`, so the deployment has provenance.
  - Aligns with the existing version-source-of-truth pattern (`version.txt` → Makefile). Same idea, one level up.
  - Helper is easy to test with a temp `CHANGELOG.md` fixture.
- **Cons:**
  - Adds a new file at the repo root (mild).
  - Requires re-syncing the 22 historical lines from the `.m` block into `CHANGELOG.md` on the first apply (mechanical, ~5 min).
  - Slight runtime overhead from file I/O on every pipeline run; negligible (one `fopen` + one `fgetl`-loop).
- **Effort:** Low-Medium.

### 2. Keep changelog in code as a cell array, return via helper

- Define `src/io/pseudo_CT_changelog.m` returning a cell array `{{'1.1', 'fill missing atlas-covered head regions with soft tissue'}, ...}`.
- `atlas_based_attenuation_map.m` calls the helper, iterates, prints. The history is still in code, but in a single typed place.
- `Makefile` would need a separate export step to dump the cell array to text for the release bundle.
- **Pros:** No new top-level file; helper is testable.
- **Cons:** Still requires editing two files per release (the `.m` cell array AND `version.txt`); the Makefile-side export is awkward in plain Make. Couples history to MATLAB execution.
- **Effort:** Medium. Worse trade-off than Approach 1 because the canonical source is still code, not data.

### 3. Extend `version.txt` with a structured changelog block

- Add a separator (e.g., a `---` line) below the version line; everything after is the changelog.
- Helper reads the file once, splits on the separator.
- **Pros:** Only one new file, no `CHANGELOG.md` to keep in sync with `version.txt`.
- **Cons:** Mixes two concerns (current version + history) into one file; the Makefile `head -n 1` trick still works for VERSION but the file becomes harder to hand-edit; the `# 2.6.0: ...` comment line already shows this drift risk (it's a different syntax from the proposed separator). Weakens the "single concern per file" principle.
- **Effort:** Low. Rejected on principle.

### 4. Do nothing

- Acknowledge the drift; keep adding to the hardcoded block per release.
- **Pros:** Zero work.
- **Cons:** Drift will recur every release; `Pseudo_CT_AC_Version.txt` keeps lying about the latest version. Three-way maintenance cost stays.
- **Effort:** Zero. Rejected.

## Recommendation

**Approach 1** — extract to a canonical `CHANGELOG.md`, add `src/io/pseudo_CT_write_version_log.m` to render it per-subject, and have the Makefile `package` target ship `CHANGELOG.md` alongside `version.txt`.

Why:

1. **Eliminates the existing drift** (`Pseudo_CT_AC_Version.txt` already says v2.5 is the latest when the repo is at v2.6.0).
2. **Aligns with the established `version.txt` + Makefile pattern.** The same single-source-of-truth principle that `release-packaging` already mandates for the version string extends naturally to the per-version history.
3. **Smaller blast radius than the alternative approaches.** The change is essentially: move 22 lines of text out of a `.m` file into a `.md` file, add a 30-line writer helper, one Makefile line, one smoke-test assertion. The pipeline's behavior (file presence, location, format header) is preserved.
4. **Prepares the ground for a future `make sync-readme` target** that would close the remaining two-way drift between `README.md` and `CHANGELOG.md`. That is explicitly out of scope here but is now straightforward.

The proposal phase should also include a small MODIFIED delta to `openspec/specs/release-packaging/spec.md` adding a requirement: "The per-subject `Pseudo_CT_AC_Version.txt` content MUST be derived from a canonical `CHANGELOG.md` at the repo root." This makes the contract explicit and prevents the drift from recurring.

## Risks

- **Historical line transcription.** The 22 lines in `atlas_based_attenuation_map.m:670-695` must be re-typed into `CHANGELOG.md` verbatim. A typo or omitted entry would silently regress the changelog. Mitigation: a one-shot smoke test that asserts the helper's output for the current `version.txt` matches the historical block (byte-equal diff against a fixture) before the migration is removed.
- **Repo-root resolution under deployed mode.** The new helper needs to find `CHANGELOG.md` at the repo root, the same way `atlas_based_attenuation_map.m:90-104` already finds `version.txt`. The pattern (`fileparts(fileparts(fileparts(mfilename('fullpath'))))` from `src/core/`, or repo-root anchor from `src/io/`) needs to be re-applied carefully in the deployed layout. The prior `umap-batchatlas-packaging` change already solved this for `version.txt`; reuse the same approach.
- **`Makefile` churn risk.** Adding `CHANGELOG.md` to the `package` target is one line, but it should be tested: confirm `make package` still produces a valid `dist/pseudoCT_v<VERSION>/` bundle with both `version.txt` and `CHANGELOG.md` at the root.
- **Smoke test brittleness.** `scripts/run_smoke_tests.m` already runs mlint on `src/`; adding a parse check for the new helper is safe but the helper should be deliberately small to keep the surface lint-clean.
- **R2010b compatibility.** The helper uses `fopen`/`fgetl`/`fclose`, all R14-era. No new MATLAB version dependency is introduced.
- **README drift persistence.** This change does NOT fix the README ↔ CHANGELOG.md drift (only the `.m` ↔ CHANGELOG.md drift). A separate, follow-up change would address that. Should be called out in the proposal as out-of-scope.

## Ready for Proposal

**Yes.** The change is well-bounded, the pain point is concrete (the existing drift is observable today), the recommended approach aligns with the established `version.txt` + Makefile pattern, and the affected files are limited.

The orchestrator should ask the user one decision before launching `sdd-propose`:

- **Format of `CHANGELOG.md` entries**: keep the current prose-style single-line per version (e.g., `- 2.6.0: unified UMAP discovery, ...`) — **recommended**, because it matches both `version.txt:2` and the per-line style currently in the `.m` block — OR a more structured format (sections per release with `## Added / ## Fixed / ## Changed`) which is more standard but requires a richer parser and bigger migration.

## Related Prior Work

- `openspec/changes/archive/2026-06-30-umap-batchatlas-packaging/` introduced `version.txt` and the Makefile `tag`/`package` targets. It explicitly noted the hardcoded changelog block as out of scope.
- `openspec/specs/release-packaging/spec.md` is the existing main spec that this change will MODIFY to cover the per-subject log content.
- `openspec/changes/local-pipeline-end-compat/` (active, separate change) touches the QC TIFF write just above the version-log write in `atlas_based_attenuation_map.m`. This change is independent and orthogonal, but both modify the end-of-pipeline block; the apply phases should not collide.
