# ute-umap-discovery Specification

## Purpose

Unified case-insensitive UTE/UMAP autodiscovery. Replaces two divergent implementations with a shared `dir()`-based helper that never crashes on empty results. Same behavior in single-subject (GUI) and batch processing.

## Requirements

### Requirement: Sibling Folder Discovery

The system MUST search sibling directories at the MPRAGE folder level for UTE/UMAP content using `dir()` — not `ls('*PAT*')` — so zero-match conditions never raise MATLAB errors.

#### Scenario: Sibling folders found

- GIVEN MPRAGE at `subject/MR/MPRAGE/` with siblings `UMAP/` and `UTE_2/`
- WHEN discovery scans sibling directories
- THEN `UMAP/` and `UTE_2/` MUST be identified as candidates

#### Scenario: No sibling folder matches

- GIVEN MPRAGE at `subject/MR/MPRAGE/` with no sibling folder matching any UTE/UMAP variant
- WHEN discovery scans sibling directories
- THEN UTE and UMAP return values MUST each equal 0

### Requirement: Case-Insensitive Pattern Matching

The system MUST match folder names case-insensitively against patterns: `umap`, `ute`, `mu_map`, `mumap`.

#### Scenario: Case variants match

- GIVEN sibling folder `Mu_Map_AC` containing `*0001*` files
- WHEN discovery performs case-insensitive matching
- THEN `Mu_Map_AC` MUST be identified as a UMAP candidate

#### Scenario: Multiple candidate sibling folders

- GIVEN siblings `MUMAP_UTE/` and `umap/` each containing `*0001*` files
- WHEN multiple case-insensitive matches exist
- THEN the first alphabetically sorted match SHALL be selected

### Requirement: Content Existence Validation

The system MUST verify a matched folder contains at least one `*0001*` file before treating it as a valid candidate.

#### Scenario: Empty matched folder excluded

- GIVEN sibling folder `umap/` matching the pattern but containing no `*0001*` files
- WHEN discovery validates folder content
- THEN the folder SHALL be excluded from candidate results

### Requirement: Unified Invocation

Both the batch path (`pseudo_CT_auto_discover_ute_umap`) and the single-subject GUI path (`load_mr_4_AC`) MUST delegate to the shared helper. The helper SHALL return identical results regardless of caller.

#### Scenario: Identical results from batch and GUI

- GIVEN the same subject directory
- WHEN the shared helper is invoked from batch code AND from GUI code
- THEN both callers MUST receive the same UTE and UMAP file paths

### Requirement: Return Value Contract

The shared helper MUST return `ute_fn=0` when no UTE found and `umap_fn=0` when no UMAP found. On success, the first matching `*0001*` full file path SHALL be returned.

#### Scenario: No UTE, UMAP found

- GIVEN a subject with sibling `umap/0001.dcm` but no UTE sibling folder
- WHEN discovery completes
- THEN `ute_fn` MUST equal 0 and `umap_fn` MUST equal the full path to `umap/0001.dcm`
