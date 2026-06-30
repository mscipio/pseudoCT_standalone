# batch-atlas-resolution Specification

## Purpose

Configurable `Batch_atlas` location supporting standalone deployment. The atlas is external to the repo and must be locatable via environment variable, default configuration, or relative fallback.

## Requirements

### Requirement: Configurable Atlas Path Resolution

The system MUST resolve the `Batch_atlas` directory using a fixed priority order: (1) `PSEUDOCT_BATCH_ATLAS` environment variable, (2) configured default in `defaults_pseudo_CT.m`, (3) repo-adjacent `Batch_atlas/` relative fallback.

#### Scenario: Environment variable overrides default

- GIVEN `PSEUDOCT_BATCH_ATLAS=/opt/shared/Batch_atlas` is set
- WHEN atlas path is resolved at runtime
- THEN the resolved path SHALL be `/opt/shared/Batch_atlas`

#### Scenario: Default used when env var absent

- GIVEN `PSEUDOCT_BATCH_ATLAS` is NOT set and `defaults_pseudo_CT.m` defines a valid path
- WHEN atlas path is resolved
- THEN the default value from `defaults_pseudo_CT.m` SHALL be used

#### Scenario: Relative fallback for development

- GIVEN neither env var nor default path resolves to an existing directory
- WHEN atlas path resolution falls back
- THEN the repo-adjacent `Batch_atlas/` directory SHALL be checked

### Requirement: Atlas Existence Validation

The system MUST verify the resolved path contains a `Batch_atlas/` directory with atlas assets before any SPM batch operation.

#### Scenario: Atlas missing from all candidates

- GIVEN every resolution candidate points to a nonexistent `Batch_atlas/`
- WHEN resolution completes
- THEN the system MUST raise a descriptive error naming every location checked

#### Scenario: Atlas found and path added

- GIVEN a resolved path points to an existing `Batch_atlas/` with atlas NIfTI files
- WHEN validation passes
- THEN the atlas path SHALL be added to the MATLAB path so SPM batch templates load correctly

### Requirement: Consumer Injection

The resolved atlas path MUST be passed to `atlas_based_attenuation_map` and `move_image_2_MNI`.

#### Scenario: Consumers receive resolved path

- GIVEN atlas resolution completes successfully
- WHEN the pipeline invokes atlas-dependent operations
- THEN both consumer functions SHALL operate under the resolved atlas path
