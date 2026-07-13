# Delta for launchpad-matlab-compat

## ADDED Requirements

### Requirement: Coregistration Parity and Divergence Documentation

Compatibility documentation MUST state `spm_run_coreg_estimate` matches between MATLAB R2010b (7.11) and compiled Launchpad v2.0 (MCR 7.11) for byte-identical input. It MUST state modern MATLAB (R2013b+, including R2026a) can produce divergent optimizer results even with identical input, SPM sources, and MEX. Documentation SHALL NOT publish machine-specific deltas and SHALL NOT claim full-pipeline parity for non-R2010b runtimes.

#### Scenario: Parity stated qualitatively

- GIVEN compatibility documentation
- THEN it SHALL state MATLAB 7.11/MCR 7.11 matches at coregistration
- AND MUST NOT include max-affine-delta values

#### Scenario: Divergence documented without overclaim

- GIVEN compatibility documentation
- THEN it SHALL state R2010b is the only runtime with bit-identical coregistration
- AND SHALL reference the PCA shim as restoring pre-coreg parity without fixing the optimizer
- AND MUST NOT claim R2026a full-pipeline parity without operator E2E

### Requirement: Legacy-Compatible PCA Behavior

The PCA wrapper in `move_image_2_MNI.m` MUST use `pseudo_ct_princomp_legacy.m` when `PSEUDOCT_USE_PRINCOMP=1` and default to modern `pca(...)` otherwise. Documentation SHALL describe this as legacy-compatible without claiming it fixes optimizer divergence.

#### Scenario: Legacy PCA restores pre-coreg geometry

- GIVEN `PSEUDOCT_USE_PRINCOMP=1`
- WHEN `move_image_2_MNI.m` calls the wrapper
- THEN the legacy `princomp` path SHALL be used
- AND the pre-coreg transform SHALL match legacy `_repos` geometry

## MODIFIED Requirements

### Requirement: Minimum MATLAB Version Documentation

`run_pseudo_CT_launchpad.m` header and `defaults_pseudo_CT_launchpad.m` MUST document minimum MATLAB as R2010b (7.11) and SHALL warn modern MATLAB (R2013b+) MAY produce divergent optimizer results.
(Previously: Documented minimum version R2010b without divergence caveat.)

#### Scenario: Header includes divergence warning

- GIVEN a user reads `run_pseudo_CT_launchpad.m`
- THEN the header SHALL state "Minimum supported MATLAB: R2010b"
- AND SHALL warn modern MATLAB may diverge at the optimizer

#### Scenario: Defaults documentation unchanged

- GIVEN a user reads `defaults_pseudo_CT_launchpad.m`
- THEN the minimum version R2010b is documented
