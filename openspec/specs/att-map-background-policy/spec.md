# att-map-background-policy Specification

## Purpose

Define the optional final attenuation-map background mask while preserving the
legacy defaults-function configuration contract. The default `'No'` policy
preserves historical Launchpad output.

## Requirements

### Requirement: Defaults-Function Resolution

The system SHALL define `zero_background = 'No'` in both
`defaults_pseudo_CT.m` and `defaults_pseudo_CT_launchpad.m`.
`pseudo_CT_zero_background_enabled` SHALL accept a defaults function handle and
resolve the key without introducing a profile or root-configuration API.

The resolver SHALL return `'Yes'` for an explicit
`PSEUDOCT_ZERO_BACKGROUND=1|true|yes` opt-in or when the defaults function
returns `'Yes'`. It SHALL return `'No'` otherwise. A missing, invalid, or
throwing defaults key SHALL fail safely to `'No'` for compatibility with older
deployed defaults.

#### Scenario: Current defaults preserve historical output

- GIVEN no environment opt-in
- WHEN either production defaults function is resolved
- THEN the resolver SHALL return `'No'`

#### Scenario: Older deployed defaults omit the key

- GIVEN a deployed defaults function that cannot return `zero_background`
- WHEN the resolver evaluates it
- THEN the resolver SHALL return `'No'` without aborting the run

### Requirement: Local Final-Mask Gate

`atlas_based_attenuation_map.m` SHALL gate only the final multiplication
`att_map.*((subj_mask_dil + (orig_mprage > 20)) > 0)` with the resolved policy.
Bone-segmentation reduction and all preceding attenuation-map processing SHALL
remain unchanged.

#### Scenario: Default local behavior

- GIVEN `zero_background = 'No'`
- WHEN local processing reaches final attenuation-map output
- THEN the final subject-mask multiplication SHALL be skipped

#### Scenario: Opt-in local behavior

- GIVEN `zero_background = 'Yes'`
- WHEN local processing reaches final attenuation-map output
- THEN the final subject-mask multiplication SHALL be applied

### Requirement: Launchpad Post-Fetch Override

The compiled Launchpad backend SHALL remain unchanged. After fetching
`att_map.nii`, `run_pseudo_CT_launchpad.m` SHALL apply the optional local mask
before DICOM conversion and output promotion only when the resolved policy is
`'Yes'`.

The mask SHALL be derived from `mprage_normalized.nii` on the fetched output
grid. If that image is missing, unreadable, or dimensionally incompatible, the
entry point SHALL warn and preserve the fetched attenuation map.

#### Scenario: Default Launchpad behavior

- GIVEN `zero_background = 'No'`
- WHEN Launchpad output is fetched
- THEN `att_map.nii` SHALL proceed to DICOM conversion unchanged

#### Scenario: Missing normalized image during opt-in

- GIVEN `zero_background = 'Yes'`
- AND `mprage_normalized.nii` is unavailable
- WHEN Launchpad output is finalized
- THEN the system SHALL warn
- AND the unmasked fetched map SHALL be preserved

### Requirement: Independent Verification

The production smoke suite SHALL verify both defaults, safe resolver fallback,
the local gate, Launchpad operation ordering, and existence/parsing of the
generic exact comparators. The policy SHALL NOT depend on removed New Segment,
backward-stage, coregistration, or optimizer investigation helpers.

### Requirement: Operator Documentation

Project documentation SHALL state that `'No'` is the historical compatibility
default and that `'Yes'` changes the output policy and may alter PET
attenuation-correction results. It SHALL also state that the compiled Launchpad
binary is unchanged.
