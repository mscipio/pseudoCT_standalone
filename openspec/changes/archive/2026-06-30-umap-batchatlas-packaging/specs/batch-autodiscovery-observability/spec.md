# Delta for batch-autodiscovery-observability

## MODIFIED Requirements

### Requirement: Missing UTE Notification

The system MUST print a message to stdout when no UTE image is discovered in any sibling folder matching UTE patterns.

(Previously: only searched hardcoded `UTE_2/`; now searches all sibling folders case-insensitively.)

#### Scenario: UTE sibling folder absent or empty

- GIVEN a subject with `MR/` present but no sibling folder matching `ute` patterns contains `*0001*` files
- WHEN shared-discovery searches sibling directories
- THEN stdout MUST name the `MR/` path and state no UTE was found

### Requirement: Missing UMAP Notification

The system MUST print a message to stdout when no UMAP is discovered after exhaustive case-insensitive sibling folder search.

(Previously: described two-phase search — standard `UMAP/` then `*UMAP*` wildcard fallback.)

#### Scenario: No UMAP found in any sibling folder

- GIVEN a subject where no sibling folder matching `umap|ute|mu_map|mumap` patterns contains `*0001*` files
- WHEN shared-discovery searches all sibling directories
- THEN stdout MUST name the `MR/` path and state no UMAP was found

#### Scenario: UMAP found via case-insensitive sibling match — silent

- GIVEN a subject where `UMAP/` does not exist but `Mu_Map_AC/0001.dcm` does as a sibling folder
- WHEN case-insensitive sibling discovery locates exactly one UMAP
- THEN no message SHALL be emitted

### Requirement: Ambiguous UMAP Candidate Notification

The system MUST print a message to stdout when multiple UMAP candidates are found in sibling folders, identifying the chosen file.

(Previously: message identified "search path (standard or wildcard)"; now sibling folder name.)

#### Scenario: Multiple UMAP candidates across sibling folders

- GIVEN a subject with siblings `umap/` and `MUMAP_UTE/` each containing `*0001*` files
- WHEN discovery selects the first alphabetically sorted match
- THEN stdout MUST identify the chosen file, the sibling folder containing it, and the ambiguity

#### Scenario: Multiple UMAP in a single sibling folder

- GIVEN a subject with sibling `UMAP/` containing two `*0001*` files
- WHEN auto-discovery selects the first candidate
- THEN stdout MUST identify the chosen file, the `UMAP/` folder, and the ambiguity
