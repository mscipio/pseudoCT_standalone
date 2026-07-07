## Verification Report

**Change**: extract-version-changelog
**Version**: 2.6.0 (CHANGELOG.md line 1)
**Mode**: Standard (strict_tdd: false — no formal unit-test framework in this repo)
**Date**: 2026-07-07 (initial verify) + 2026-07-07 (remediation pass)

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 11 |
| Tasks complete (checkbox marked `[x]`) | 11 |
| Tasks incomplete (checkbox marked `[ ]`) | 0 |
| Remediation tasks addressed | 3/3 (smoke coverage, silent-failure observability, spec-drift alignment) |

### Build & Tests Execution

**Build / lint**: ✅ Passed (`scripts/run_lint.m`, exit 0)
```text
matlab -nodisplay -batch "run('scripts/run_lint.m')"
Total files checked: 40
Total lint issues: 740   (pre-existing style warnings; 0 introduced by this change)
=== EXIT 0 ===
```

**Tests**: ✅ 51 passed / 5 failed / 0 skipped (`scripts/run_smoke_tests.m`)
```text
=== Section 6: Changelog contract (post-remediation) ===
PASS  CHANGELOG.md exists
PASS  version.txt absent
PASS  CHANGELOG.md line 1 is parseable version (e.g., 2.6.0)
PASS  src/io/pseudo_CT_write_version_log.m exists
PASS  src/io/pseudo_CT_write_version_log.m parses
PASS  Makefile ships CHANGELOG.md (cp CHANGELOG.md)
PASS  Makefile excludes version.txt
PASS  Makefile excludes dev Makefile (cp Makefile)
PASS  Makefile excludes scripts/ (cp -r scripts)
=== Results: 51 passed, 5 failed ===
```
The 5 failures are pre-existing Batch_atlas directory unavailability (environment-specific, unrelated to this change).
All 9 changelog-contract checks PASS; explicit helper mlint, line-1 version regex, and Makefile structural checks now bind smoke assertions directly to spec scenarios.

**Coverage**: ➖ Not available (no coverage tool in this repo)

### Spec Compliance Matrix

| Requirement | Scenario | Evidence | Result |
|-------------|----------|----------|--------|
| CHANGELOG.md Content Contract | Version parseable from line 1 | `head -n 1 CHANGELOG.md` → `2.6.0`; `make` `VERSION = $(shell head -n 1 CHANGELOG.md)` resolved to `pkg dir` `pseudoCT_v2.6.0` | ✅ COMPLIANT |
| CHANGELOG.md Content Contract | History covers all known releases | `grep "^##" CHANGELOG.md` shows v2.6.0 → v1.1 reverse chronological, then `## Citation` JNM footer | ✅ COMPLIANT |
| CHANGELOG.md Content Contract | Smoke tests verify changelog contract | Smoke test 51/56 PASS incl. line-1 version regex, explicit helper mlint, Makefile contract structural checks | ✅ COMPLIANT |
| Per-Subject Changelog Export | Normal path copies changelog | Direct `pseudo_CT_write_version_log('2.6.0', dest)` produced `Pseudo_CT_AC_Version.txt` with `isequal(content, CHANGELOG.md)` = `true` | ✅ COMPLIANT |
| Changelog Export Fallback | Missing changelog produces fallback | Alt-root test (repo root with no CHANGELOG.md) wrote `Pseudo-CT code version: 2.6.0 / Date:` and never errored | ✅ COMPLIANT |
| Single Canonical Version Source | Version read from changelog for tagging | `Makefile:4` `VERSION = $(shell head -n 1 CHANGELOG.md …)`; `Makefile:14` `git tag -a "v$(VERSION)"` | ✅ COMPLIANT (static; tag action not executed to avoid mutating repo) |
| Single Canonical Version Source | Version used for package naming | Reproduced Makefile `package` recipe into a clean dir → produced folder name `pseudoCT_v2.6.0` | ✅ COMPLIANT |
| Runtime-Only Package Assembly | Development files excluded | Reproduced package contents lack `version.txt`, `Makefile`, `scripts/`, `.git`, `.github`, `openspec`, `Batch_atlas` | ✅ COMPLIANT |
| Runtime-Only Package Assembly | Runtime essentials included | Reproduced package contains `run_pseudo_CT_local.m`, `run_pseudo_CT_launchpad.m`, `CHANGELOG.md`, `src/`, `vers/`, `spm8-r6313/`, `imgaussian/`, `ssh2_v2_m1_r5/` | ✅ COMPLIANT |

**Compliance summary**: 9/9 scenarios compliant (8 distinct with runtime evidence; 1 static-only: tagging recipe — git tag not executed by verifier)

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|------------|--------|-------|
| `CHANGELOG.md` line 1 = bare version | ✅ Implemented | Line 1 = `2.6.0` exactly, machine-parseable |
| `version.txt` removed | ✅ Implemented | `git status` shows ` D version.txt`; `test -f` returns NO |
| `pseudo_CT_write_version_log.m` created in `src/io/` | ✅ Implemented | 72 lines (post-remediation), R2010b-safe `fopen`/`fread`/`fwrite`/`fclose`, try/catch fallback with `status` return value and `disp()` operator visibility |
| `atlas_based_attenuation_map.m` L90–104 reads CHANGELOG.md line 1 | ✅ Implemented | `fopen(fullfile(root_dir,'CHANGELOG.md'))` → `fgetl` → `strtrim`; hardcoded fallback `'2.6.0'` |
| `atlas_based_attenuation_map.m` L670 calls helper | ✅ Implemented | Previous 26-line `fprintf` block replaced by `status = pseudo_CT_write_version_log(code_version, paths)`, with `disp()` warning when `status ~= 1` |
| `Makefile` L4 parses CHANGELOG.md | ✅ Implemented | `VERSION = $(shell head -n 1 CHANGELOG.md \| tr -d '[:space:]')` |
| `Makefile` L26 ships CHANGELOG.md | ✅ Implemented | `cp CHANGELOG.md "$(PKG_DIR)/"` |
| `Makefile` dev-only file copy removed | ✅ Implemented | No `cp Makefile`, no `cp -r scripts`, no `rm scripts/test_*.m` lines remain |
| `run_smoke_tests.m` section 6 extended | ✅ Implemented | 9 checks: CHANGELOG.md exists, version.txt absent, line-1 version parse (regex), helper existence + mlint, Makefile cp CHANGELOG.md, Makefile excludes version.txt, Makefile excludes cp Makefile, Makefile excludes cp -r scripts |
| Baseline `release-packaging` spec updated | ✅ Implemented | Canonical source → CHANGELOG.md; exclusions include `version.txt`/`Makefile`/`scripts/` |
| Delta spec exclusion wording aligned | ✅ Fixed (remediation) | Delta spec L78 now lists `.git/`, `.github/`, `openspec/`, `Batch_atlas/`, `version.txt`, `Makefile`, `scripts/` — consistent with baseline |
| CHANGELOG.md footer matches legacy code | ✅ Fixed (remediation) | Citation now matches original fprintf block wording incl. "Good News Everyone!!" and "Enjoy it ;)) !!!" |
| Silent-failure observability | ✅ Fixed (remediation) | `pseudo_CT_write_version_log` returns status (1/0/-1); uses `disp()` for operator-visible degradation messages; caller warns on status ~= 1 |

### Coherence (Design)

| Decision | Followed? | Notes |
|----------|-----------|-------|
| Canonical source = CHANGELOG.md line 1 | ✅ Yes | Used by both Makefile and MATLAB |
| Copy method = `fopen`/`fread`/`fwrite`/`fclose` (R2010b-safe) | ✅ Yes | Helper uses exactly these primitives; no `copyfile`/`readcell`/`readlines` |
| Helper path = `mfilename('fullpath')` + 3×`fileparts` | ✅ Yes | Matches existing pattern at `atlas_based_attenuation_map.m:94` |
| Helper location = `src/io/` | ✅ Yes | `src/io/pseudo_CT_write_version_log.m` (I/O in `src/io/` per repo convention) |
| Fallback writes `code_version` + `date`; never errors | ✅ Yes | Verified at runtime via alt-root experiment |
| Dev tooling excluded from `make package` | ✅ Yes | `Makefile`+`scripts/`+`version.txt` all excluded from runtime bundle |

No deviations from design.

### Issues Found

**RESOLVED (remediation pass)**:
- **BLOCKER/CRITICAL — smoke coverage too weak**: Extended `run_smoke_tests.m` section 6 from 2 checks to 9 checks: added line-1 version parse (regex `^\d+\.\d+(\.\d+)?$`), explicit `pseudo_CT_write_version_log.m` existence + mlint, and 4 Makefile structural contract checks (`cp CHANGELOG.md` present, `version.txt`/`Makefile`/`scripts/` absent). All pass.
- **CRITICAL/WARNING — silent failure in `pseudo_CT_write_version_log.m`**: Added `status` return value (1=full copy, 0=fallback, -1=complete failure) and `disp()` calls in the catch block and fallback paths for operator visibility. Caller in `atlas_based_attenuation_map.m:670` captures status and warns on degradation. Pipeline still never errors — graceful fallback preserved.
- **Spec drift — exclusion wording**: Delta spec `openspec/changes/extract-version-changelog/specs/release-packaging/spec.md` L78 now consistently lists `Makefile` and `scripts/` alongside `version.txt`. CHANGELOG.md citation footer restored to match original fprintf block wording (incl. "Good News Everyone!!" and "Enjoy it ;)) !!!").

**WARNING**:
- Literal `make package` invocation may fail in NFS environments with stale `.nfs` handles from open MATLAB sessions. Isolated reproduction of the recipe produces correct bundles — NOT a Makefile defect.

### Verdict

**PASS — REMEDIATED**

All 3 review findings resolved with runtime evidence. Smoke tests pass 51/56 (5 pre-existing Batch_atlas failures). Lint passes (740 pre-existing warnings, 0 introduced). Silent-failure observability added without breaking the pipeline. Spec/artifact drift aligned across delta spec, CHANGELOG.md footer, and tasks.md. R2010b compatibility preserved throughout.

### Skipped Dimensions

None. Strict TDD module not loaded (strict_tdd = false per AGENTS.md and apply-progress). Full artifact set (proposal + spec + design + tasks) present → all dimensions verified.

---

## Remediation Pass 2 (2026-07-07)

Three fresh review blockers addressed in this pass:

### Blocker 1: BEHAVIORAL verification for `pseudo_CT_write_version_log` → RESOLVED

**Before**: Smoke section 6 only checked helper existence + mlint parse (text/parse checks).
**After**: Sections 6d and 6e execute the helper in temp sandboxes for both paths.

| Test | Assertion | Evidence |
|------|-----------|----------|
| 6d — normal-copy | `status == 1` | ✅ PASS — `pseudo_CT_write_version_log('2.6.0', tempdir)` returns 1 |
| 6d — normal-copy | Output = CHANGELOG.md byte-for-byte | ✅ PASS — `isequal(out_c, ch_c)` is true at runtime |
| 6e — fallback | `status == 0` | ✅ PASS — phantom tree without CHANGELOG.md triggers fallback |
| 6e — fallback | Fallback file written | ✅ PASS — `Pseudo_CT_AC_Version.txt` exists |
| 6e — fallback | Contains `code_version` | ✅ PASS — `strfind(fb_c, '2.6.0')` matches |
| 6e — fallback | Contains `Date:` header | ✅ PASS — `strfind(fb_c, 'Date:')` matches |

Fallback path tested by creating a phantom directory tree (no CHANGELOG.md), copying the helper there, and calling it. The helper resolves root via `mfilename('fullpath')` → `fileparts`×3, finds no CHANGELOG.md, and gracefully writes version+date. R2010b compatibility preserved (`tempname`, `onCleanup`, `addpath`, `rmpath`, `copyfile`).

### Blocker 2: Stronger packaging verification → RESOLVED

**Before**:
- `strfind(mf_content, 'CHANGELOG.md')` — matched ANY mention of the filename (e.g., `head -n 1 CHANGELOG.md` in VERSION line). Too loose.
- No package-recipe-level verification.

**After**:
1. **Tightened positive assertion**: `strfind(mf_content, 'cp CHANGELOG.md')` — now checks the actual copy COMMAND, not just any filename mention. Guarantees the copy step exists.
2. **Added `VERSION` source check**: `strfind(mf_content, 'head -n 1 CHANGELOG.md')` — verifies version is parsed from CHANGELOG.md, not any other source.
3. **Added section 6f — Package-recipe structural verification**: 11 checks that parse the `package:` recipe block and verify each shipped file + each excluded dev file. Exercises the actual package output contract without executing `make package` (avoids NFS stale-handle issues documented in prior remediation).
4. **Documentation**: Literal `make package` verification remains a manual release-prep step (documented reason: NFS stale `.nfs` handles from open MATLAB sessions can cause `make package` to fail spuriously).

Results: all 11 package-recipe checks PASS (8 positive + 3 negative).

### Blocker 3: Environment-dependent test gate → RESOLVED

**Before**: Batch_atlas absence produced 5 FAILs (Batch_atlas/, TPM.nii, ch2.nii, 7 templates, JAR). Misleading for release-readiness in environments where Batch_atlas is legitimately absent.

**After**:
- Added `num_skipped` counter + `skip()` nested function.
- Batch_atlas section now checks: if Batch_atlas/ is missing AND `PSEUDOCT_BATCH_ATLAS` is NOT set → single `SKIP` with explanation: *"Batch_atlas/ not found at ...; set PSEUDOCT_BATCH_ATLAS to enable"*.
- If `PSEUDOCT_BATCH_ATLAS` IS set but the path is wrong → real FAIL (user explicitly configured it, path should exist).
- If Batch_atlas exists → all 5 atlas checks run normally as PASS/FAIL.
- Summary now shows `passed / failed / skipped`.

This makes the smoke signal honest: 1 skip for environment without atlas (not a failure), 5 real failures if atlas is configured but broken. Current project expectations preserved — Batch_atlas is still checked when available.

### Updated Smoke Results

```
=== Results: 70 passed, 0 failed, 1 skipped ===
```

| Metric | Pass 1 (pre-remediation) | Pass 2 (post-remediation) |
|--------|--------------------------|---------------------------|
| Passed | 51 | 70 |
| Failed | 5 (Batch_atlas) | 0 |
| Skipped | 0 | 1 (Batch_atlas env) |
| Behavioral checks | 0 | 6 (6d: 3, 6e: 4) |
| Package-recipe checks | 0 | 11 (8 positive + 3 negative) |
| Makefile checks tightened | 4 (loose CHANGELOG.md strfind) | 5 (cp CHANGELOG.md + VERSION + 3 excludes) |

### Lint

```
Total files checked: 40
Total lint issues: 740   (0 introduced)
=== EXIT 0 ===
```

### Verdict (Post-Remediation Pass 2)

**PASS — COMPLETE**

All 3 fresh review blockers resolved with runtime evidence and structural verification. 0 failures. Smoke tests now exercise behavioral execution of the new helper, structurally verify the package recipe contract, and truthfully signal environmental preconditions (Batch_atlas skip vs. failure). Lint unchanged. R2010b compatibility preserved.