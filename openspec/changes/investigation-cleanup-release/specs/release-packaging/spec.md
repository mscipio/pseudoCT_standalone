# Delta for release-packaging

## ADDED Requirements

### Requirement: Release Notes Completeness

The CHANGELOG.md minor-release entry MUST include the qualitative coregistration-parity finding, an R2026a deferred-validation warning, and a list of excluded investigation artifacts with rationale. The finding SHALL NOT include machine-specific numeric deltas.

#### Scenario: Finding stated qualitatively

- GIVEN the release notes
- THEN they SHALL state MATLAB 7.11/MCR 7.11 matches compiled Launchpad at coregistration
- AND SHALL state modern MATLAB can diverge downstream
- AND MUST NOT contain max-affine-delta values

#### Scenario: Deferred-validation warning present

- GIVEN the release notes discuss modern-runtime compatibility
- THEN an explicit warning SHALL state R2026a E2E validation is deferred pending operator run
- AND SHALL state the compiled Launchpad v2.0 binary is unchanged

#### Scenario: Cleanup exclusions documented

- GIVEN the release notes
- THEN excluded artifacts SHALL be listed with removal reason
- AND `spm8-dan/` SHALL be listed as gitignored parity-testing tree
