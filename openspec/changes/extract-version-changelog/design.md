# Design: Extract Version Changelog

## Technical Approach

Replace `version.txt` with `CHANGELOG.md` as the single canonical artifact. **Line 1 is the bare version** (parseable by Makefile and MATLAB). Remaining content is reverse-chronological history with the JNM citation footer. At pipeline end, the hardcoded `fprintf` block in `atlas_based_attenuation_map.m:669–695` is replaced by a call to `src/io/pseudo_CT_write_version_log.m` that copies `CHANGELOG.md` verbatim to `Pseudo_CT_AC_Version.txt` using only R2010b-safe I/O (`fopen`/`fread`/`fwrite`/`fclose`). If `CHANGELOG.md` is absent, the helper writes a fallback with `code_version` + `date` and **never errors**.

As part of the same change, `make package` is cleaned up to exclude all dev-only files from the runtime bundle: `Makefile` and the entire `scripts/` directory are removed alongside `version.txt`.

## Architecture Decisions

| Decision | Alternatives | Choice | Rationale |
|---|---|---|---|
| Canonical version source | `version.txt`; embed in `.m`; structured block | `CHANGELOG.md` with bare version on line 1 | Eliminates 3-way drift; single file per concern |
| Copy method at pipeline end | `copyfile`; shell escape | `fopen`/`fread`/`fwrite`/`fclose` | R2010b-era primitives per spec; safe in deployed mode |
| Helper path resolution | Pass from caller | `mfilename('fullpath')` + 3×fileparts | Matches existing pattern at `atlas_based_attenuation_map.m:94`; self-contained |
| Helper location | Inline; `src/core/` | `src/io/pseudo_CT_write_version_log.m` | I/O in `src/io/` per repo convention; testable independently |
| Fallback when CHANGELOG.md unreadable | Error; empty file | `code_version` + `date` | Pipeline must not fail for non-critical metadata |
| Dev tooling in runtime package | Keep `Makefile`+`scripts/` | Exclude both from `make package` | All three `scripts/` files are CI/dev-only; `Makefile` has no runtime role. In-scope for the same release-packaging change — aligns with "Runtime-Only Package Assembly" |

## Data Flow

```
CHANGELOG.md (repo root)
    ├─→ Makefile: head -n 1 → VERSION (tag + package)
    ├─→ atlas_based_attenuation_map.m: fopen/fgetl → code_version
    └─→ pseudo_CT_write_version_log(code_version, paths)
          ├─ [normal]  copy CHANGELOG.md → Pseudo_CT_AC_Version.txt
          └─ [fallback] version + date → Pseudo_CT_AC_Version.txt
```

## File Changes

| File | Action | Description |
|---|---|---|
| `CHANGELOG.md` | Create | Line 1 = `2.6.0`; history v2.6.0→v1.1; JNM footer |
| `version.txt` | Delete | Replaced by `CHANGELOG.md` line 1 |
| `Makefile` | Modify | L4: parse `CHANGELOG.md`; L26: `cp CHANGELOG.md`; L32–34: remove `cp Makefile`, `cp -r scripts`, `rm -f scripts/test_auto_discover_messages.m` |
| `src/core/atlas_based_attenuation_map.m` | Modify | L90-104: read `CHANGELOG.md`; L669-695: replace `fprintf` block with helper call |
| `src/io/pseudo_CT_write_version_log.m` | Create | R2010b-safe copy via `fopen`/`fread`/`fwrite`/`fclose`; fallback on failure |
| `scripts/run_smoke_tests.m` | Modify | Assert CHANGELOG.md exists, helper parses, package excludes dev files |
| `openspec/specs/release-packaging/spec.md` | Modify | Canonical source → `CHANGELOG.md`; package excludes `version.txt`, `Makefile`, `scripts/` |

## Interfaces

```matlab
function pseudo_CT_write_version_log(code_version, dest_dir)
% Writes Pseudo_CT_AC_Version.txt to dest_dir.
% Never errors — fallback writes version + date.
```

`code_version` is resolved by the caller (lines 90–104 of `atlas_based_attenuation_map.m`). The helper handles changelog path resolution and copy/fallback.

## Path Resolution in Deployed Layouts

Both the version-read block and helper use `fileparts(fileparts(fileparts(mfilename('fullpath'))))` to reach repo root. In compiled (`mcc`) mode, `mfilename('fullpath')` returns `''`, resolving to CWD-relative `CHANGELOG.md`. The try/catch fallback (hardcoded `code_version`; version+date) ensures pipeline continuation.

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Smoke | CHANGELOG.md exists; helper parses; version.txt absent | Extend `run_smoke_tests.m` with `exist()` + `mlint()` |
| Unit | Helper copies valid fixture; fallback on missing CHANGELOG.md | Manual verification script with temp files |
| Integration | `make package` ships CHANGELOG.md, excludes version.txt, Makefile, scripts/ | Inspect `dist/` contents post-build |

No formal test framework; manual verification supplements CI smoke tests.

## Migration / Rollout

1. Create `CHANGELOG.md` (transcribe + prepend `2.6.0`)
2. Implement `pseudo_CT_write_version_log.m`
3. Update `atlas_based_attenuation_map.m` (read + write blocks)
4. Update Makefile (L4, L26, L32–34)
5. Update smoke tests + spec
6. Delete `version.txt`
7. `make test`

**Rollback**: Restore `version.txt`, Makefile L4/L32–34, and the `fprintf` block; delete new files.

## Open Questions

None. All risks resolved by design.
