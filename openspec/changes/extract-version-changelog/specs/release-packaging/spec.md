# Delta for release-packaging

## ADDED Requirements

### Requirement: CHANGELOG.md Content Contract

`CHANGELOG.md` SHALL be the single canonical artifact for version and release history.
- Line 1 MUST contain only the current version (e.g., `2.6.0`), machine-parseable.
- Remaining content MUST be reverse chronological full history including minor/patch versions.
- Footer MUST include the JNM citation and acknowledgment.

#### Scenario: Version parseable from line 1

- GIVEN `CHANGELOG.md` with `2.6.0` on line 1
- WHEN `make tag` or runtime reads line 1
- THEN the version SHALL resolve to `2.6.0`

#### Scenario: History covers all known releases

- GIVEN the pipeline has exported version logs since v1.1
- WHEN a release is cut
- THEN all prior versions SHALL appear in reverse chronological order above the footer

#### Scenario: Smoke tests verify changelog contract

- GIVEN the project root
- WHEN smoke tests run
- THEN they SHALL assert `CHANGELOG.md` exists AND the export source parses with no R2010b-incompatible syntax

### Requirement: Per-Subject Changelog Export

The pipeline MUST write `Pseudo_CT_AC_Version.txt` as an exact local copy of `CHANGELOG.md` for each processed subject. The export SHALL use only R2010b-safe I/O (`fopen`/`fread`/`fwrite`/`fclose`).

#### Scenario: Normal path copies changelog

- GIVEN `CHANGELOG.md` is accessible at the repo root
- WHEN the pipeline completes processing for one subject
- THEN `Pseudo_CT_AC_Version.txt` SHALL be written to the subject's processing directory with identical content to `CHANGELOG.md`

### Requirement: Changelog Export Fallback

If `CHANGELOG.md` cannot be read (deployed or unusual layout), the pipeline MUST write a minimal fallback file containing the runtime-resolved `code_version` and date. The pipeline MUST NOT fail or error.

#### Scenario: Missing changelog produces fallback

- GIVEN `CHANGELOG.md` is absent or unreadable at pipeline end
- WHEN the pipeline reaches the version-log export step
- THEN a `Pseudo_CT_AC_Version.txt` SHALL be written with at least the version and date AND the pipeline SHALL continue normally

## MODIFIED Requirements

### Requirement: Single Canonical Version Source

The system MUST use `CHANGELOG.md` line 1 as the single source of truth for the release version.
(Previously: used `version.txt` as the canonical version source)

#### Scenario: Version read from changelog for tagging

- GIVEN `CHANGELOG.md` line 1 is `2.6.0`
- WHEN `make tag` is invoked
- THEN a git tag matching the version string SHALL be created

#### Scenario: Version used for package naming

- GIVEN `CHANGELOG.md` line 1 is `2.6.0`
- WHEN `make package` assembles the release folder
- THEN the output folder SHALL be named with the same version

### Requirement: Runtime-Only Package Assembly

`make package` MUST include `CHANGELOG.md` and MUST NOT include `version.txt`.
(Previously: included `version.txt`, did not include a changelog)

#### Scenario: Development files excluded

- GIVEN the full repository
- WHEN `make package` runs
- THEN the output MUST NOT contain `.git/`, `.github/`, `openspec/`, `Batch_atlas/`, `version.txt`, `Makefile`, or `scripts/`

#### Scenario: Runtime essentials included

- GIVEN a successful `make package` run
- WHEN inspecting the output folder
- THEN it MUST contain entry-point scripts, `src/`, `vers/`, `spm8-r6313/`, `imgaussian/`, `ssh2_v2_m1_r5/`, and `CHANGELOG.md`
