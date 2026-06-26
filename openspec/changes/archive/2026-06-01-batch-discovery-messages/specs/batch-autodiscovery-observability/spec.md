# batch-autodiscovery-observability Specification

## Purpose

Console visibility into UTE/UMAP auto-discovery outcomes during batch execution. Operators need traceable messages naming the subject and reason when subjects are silently skipped.

## Requirements

### Requirement: Missing MR Parent Path Notification

The system MUST print a message to stdout when the MPRAGE path lacks a recognizable `MR/` directory.

#### Scenario: MR parent path not found

- GIVEN an MPRAGE file at a path lacking an `MR/` directory
- WHEN `pseudo_CT_auto_discover_ute_umap` cannot locate `MR/`
- THEN stdout MUST contain the subject path and an indication that no MR parent was found

### Requirement: Missing UTE Notification

The system MUST print a message to stdout when no UTE image is discovered.

#### Scenario: UTE directory absent or empty

- GIVEN a subject with `MR/` present but no `UTE_2/*0001.*` files
- WHEN auto-discovery searches for UTE images
- THEN stdout MUST name the `MR/` path and state no UTE was found

### Requirement: Ambiguous UTE Candidate Notification

The system MUST print a message to stdout when multiple UTE candidates are found, identifying the chosen file.

#### Scenario: Multiple UTE images in directory

- GIVEN a subject with `UTE_2/` containing three `*0001.*` files
- WHEN auto-discovery selects the first candidate
- THEN stdout MUST identify the chosen file and note multiple candidates were present

### Requirement: Missing UMAP Notification

The system MUST print a message to stdout when no UMAP is discovered after exhausting both the standard `UMAP/` search and the wildcard `*UMAP*` fallback.

#### Scenario: No UMAP found

- GIVEN a subject where neither `UMAP/*0001.*` nor `*UMAP*/*0001.*` exists
- WHEN both UMAP discovery strategies fail
- THEN stdout MUST name the `MR/` path and state no UMAP was found

#### Scenario: UMAP found via wildcard — silent

- GIVEN a subject where `UMAP/` does not exist but `MR_UMAP/*0001.*` does
- WHEN wildcard fallback discovers exactly one UMAP
- THEN no message SHALL be emitted

### Requirement: Ambiguous UMAP Candidate Notification

The system MUST print a message to stdout when multiple UMAP candidates are found, identifying the chosen file and search path (standard or wildcard).

#### Scenario: Multiple UMAP in standard directory

- GIVEN a subject with `UMAP/` containing two `*0001.*` files
- WHEN auto-discovery selects the first candidate
- THEN stdout MUST identify the chosen file, the `UMAP/` path, and the ambiguity

#### Scenario: Multiple UMAP in wildcard-discovered directory

- GIVEN a subject with `MR_UMAP/` containing multiple `*0001.*` files and no `UMAP/`
- WHEN wildcard fallback discovers the directory and multiple candidates exist
- THEN stdout MUST identify the chosen file, the wildcard path, and the ambiguity

### Requirement: Return Value Preservation

The function MUST preserve its existing return-value contract. No return value SHALL change: `ute_fn=0` when no UTE found, `umap_fn=0` when no UMAP found, first file path when candidates exist.

#### Scenario: Return values unchanged for missing UTE

- GIVEN a subject with no UTE images
- WHEN the function completes with observability messages
- THEN `ute_fn` MUST equal 0 and `umap_fn` MUST retain its existing value

#### Scenario: Return values unchanged for ambiguous case

- GIVEN a subject with two UTE candidates
- WHEN the function completes with observability messages
- THEN `ute_fn` MUST equal the full path of the first candidate (unchanged)

### Requirement: Message Survivability Under Warning Suppression

The system MUST use `fprintf` to stdout (not `warning()`) for all observability messages, so they survive global `warning('off','all')` in batch mode.

#### Scenario: Messages visible when warnings suppressed

- GIVEN a batch run with `warning('off','all')` active
- WHEN auto-discovery emits a missing UMAP notification
- THEN the message MUST appear in console output
