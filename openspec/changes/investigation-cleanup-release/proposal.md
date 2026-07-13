# Proposal: Investigation Cleanup Release

## Intent

Prepare a minor release that makes the runtime-divergence investigation durable and reviewable: document verified MATLAB/MCR compatibility findings qualitatively, keep reusable diagnostics, clean generated investigation artifacts, and preserve user work without changing production behavior during cleanup.

## Scope

### In Scope
- Document the verified finding: MATLAB 7.11/MCR 7.11 matches compiled Launchpad at coregistration; modern MATLAB can diverge downstream, without publishing machine-specific measured deltas.
- Keep reusable comparison/restart diagnostics and their supporting compatibility helpers.
- Remove or ignore generated/investigative artifacts, including removing the untracked local `spm8-dan/` reference tree from the repo workspace.
- Prepare minor-release readiness: changelog, packaging boundary, lint/smoke verification, commit/push/tag plan, and explicit warning that real R2026a local E2E validation is deferred.

### Out of Scope
- Rebuilding or modifying the compiled Launchpad backend.
- Claiming R2026a full-pipeline parity before an operator E2E run.
- Deleting intended source, OpenSpec artifacts, `TODO.md`, or reusable diagnostics.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `release-packaging`: minor-release notes and package boundary must include the investigation finding, deferred-validation warning, and cleanup exclusions.
- `entrypoint-divergence-diagnostics`: diagnostic scripts must remain reviewable, reusable, and documented as investigation tools.
- `launchpad-matlab-compat`: compatibility documentation must distinguish verified R2010b/MCR 7.11 parity from modern-runtime divergence.

## Approach

Use cleanup-first release preparation: classify files, preserve user work, remove only generated scratch, document the finding in `CHANGELOG.md`/release docs, keep warnings explicit, then verify and prepare reviewable work-unit commits under the 800-line budget.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `CHANGELOG.md` | Modified | Minor-release entry and warning. |
| `.gitignore` / workspace scratch | Modified/Removed | Exclude or remove generated investigation artifacts. |
| `scripts/`, `src/config/`, `src/core/` | Modified | Preserve reusable diagnostics/helpers. |
| `openspec/changes/*`, `openspec/specs/*` | Modified | Keep active specs/artifacts coherent. |
| `dist/` / release packaging | Modified | Regenerate only after verification. |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Overclaiming compatibility | Med | Qualitative wording plus deferred E2E warning. |
| Accidental deletion of user work | Low | Classify before cleanup; preserve `TODO.md` and SDD artifacts. |
| Repo bloat from reference trees | High | Remove local `spm8-dan/` and ignore it. |

## Rollback Plan

Revert cleanup/release commits before tagging; restore any removed scratch from local backups if needed. No production code is deleted by this proposal phase.

## Dependencies

- Existing exploration evidence from OpenSpec and Engram.
- Operator acceptance that R2026a E2E validation is deferred.

## Success Criteria

- [ ] Minor-release docs state verified findings and deferred-validation warning.
- [ ] Generated artifacts are cleaned without losing intended work.
- [ ] Lint/smoke/package checks are ready for verify.
- [ ] Review boundary stays within 800 changed lines.
