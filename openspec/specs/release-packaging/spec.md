# release-packaging Specification

## Purpose

Single version source, automated git tagging, and runtime-only deployable folder assembly. Excludes development files and the external `Batch_atlas/` from release packages.

## Requirements

### Requirement: Single Canonical Version Source

The system MUST use `version.txt` as the single source of truth for the release version. The file SHALL contain one plain-text version line.

#### Scenario: Version read for tagging

- GIVEN `version.txt` contains `2.6.0`
- WHEN `make tag` is invoked
- THEN a git tag matching the version string SHALL be created

#### Scenario: Version used for package naming

- GIVEN `version.txt` contains `2.6.0`
- WHEN `make package` assembles the release folder
- THEN the output folder SHALL be named with the same version

### Requirement: Tag Consistency

The content of `version.txt` MUST match the release tag applied by the Makefile.

#### Scenario: Package version matches tag

- GIVEN git tag `v2.6.0` exists and `version.txt` reads `2.6.0`
- WHEN the package is assembled
- THEN the included `version.txt` SHALL be identical to the tagged source

### Requirement: Runtime-Only Package Assembly

`make package` MUST assemble a folder containing only files needed to run the pipeline and MUST NOT include development artifacts.

#### Scenario: Development files excluded

- GIVEN the full repository
- WHEN `make package` runs
- THEN the output MUST NOT contain `.git/`, `scripts/test_*.m`, `.github/`, `openspec/`, or `Batch_atlas/`

#### Scenario: Runtime essentials included

- GIVEN a successful `make package` run
- WHEN inspecting the output folder
- THEN it MUST contain entry-point scripts, `src/`, `vers/`, `spm8-r6313/`, `imgaussian/`, `ssh2_v2_m1_r5/`, and `version.txt`

### Requirement: Versioned Release Layout

The deployment root SHALL contain versioned release folders and a `Batch_atlas/` shared across releases.

#### Scenario: Multiple releases coexist

- GIVEN releases `v2.5.0` and `v2.6.0` deployed
- WHEN listing the deployment root
- THEN both versioned folders SHALL exist alongside a single shared `Batch_atlas/`

#### Scenario: Latest symlink accessible

- GIVEN the most recent deployment is `v2.6.0`
- WHEN an operator invokes an entry point via a "latest" symlink
- THEN the entry point SHALL execute from the `v2.6.0` release folder
