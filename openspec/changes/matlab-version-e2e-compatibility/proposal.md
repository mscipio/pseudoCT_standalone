# Proposal: MATLAB Version E2E Compatibility

## Intent

Provide a repeatable operator matrix that compares every local artifact with the fixed Launchpad reference at `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/test_data_launchpad`. This is diagnostic infrastructure, not a runtime-parity fix.

## Scope

### In Scope
- Operator procedure, existing fixture, and preserved run archives.
- Additive wrapper using `/usr/pubsw/bin/matlab*` for R2010b, R2013b, R2018b, R2022b, and R2026a, with `PSEUDOCT_USE_PRINCOMP=0` and `=1` sweeps.
- Additive aggregator comparing every archived file in `MR_PET/tmp`, `MR_PET`, and `MR/pseudo_muMAP` with its Launchpad counterpart.
- Final `compatibility.md`: native- and legacy-PCA tables; pipeline-step rows; one column per version; cells show `compared/expected`, maximum voxel/pixel difference, and mismatch count/status.

### Out of Scope
- Pipeline sources, defaults, comparator behavior, fixtures, CI, or the compiled Launchpad backend.
- Release-cleanup files, `CHANGELOG.md`, and automated matrix CI.

## Capabilities

### New Capabilities
- `matlab-version-e2e-compatibility`: Five-version, dual-PCA, full-artifact local-to-Launchpad comparison with a quantitative stage-by-stage Markdown matrix.

### Modified Capabilities
None — `entrypoint-divergence-diagnostics` is consumed unchanged.

## Approach

Add `docs/matlab-version-compat-E2E.md`, `scripts/run_matlab_version_e2e.sh`, and `scripts/run_matlab_version_e2e_report.m`. Preserve every output, inventory it one-to-one against Launchpad, retain `LOCAL_ONLY`/`LAUNCHPAD_ONLY` results, apply existing comparison semantics, and group by pipeline order. Missing or unclassified artifacts fail coverage.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `docs/matlab-version-compat-E2E.md` | New | Operator procedure and report contract |
| `scripts/run_matlab_version_e2e.sh` | New | Matrix runner using `/usr/pubsw/bin/matlab*` |
| `scripts/run_matlab_version_e2e_report.m` | New | Full-artifact aggregation and Markdown matrix |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Cleanup overlap | Medium | Add only the three named artifacts; change no existing source, CI, or changelog |
| Unavailable MATLAB | Medium | Record an actionable skip; never substitute an executable |
| Missing/unmatched reference | High | Report incomplete coverage; never omit a local artifact |
| Environment or metadata noise | Medium | Report it separately from semantic voxel/pixel divergence |

## Rollback Plan

Remove the three additive artifacts and generated reports; pipeline behavior remains unchanged.

## Dependencies

- Existing fixture, Launchpad reference tree, `PSEUDOCT_KEEP_TMP`, and `diff_entrypoint_runs.m`.
- Approved MATLAB executables exposed by `/usr/pubsw/bin/matlab*`.

## Success Criteria

- [ ] Both PCA modes run, or produce an actionable skip, for all five approved runtimes.
- [ ] Every successful local artifact has a visible comparison record against `/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/test_data_launchpad`.
- [ ] `compatibility.md` has two Markdown matrices with pipeline-step rows, five version columns, and quantitative divergence in every applicable cell.
- [ ] No pipeline source, comparator, CI workflow, changelog, or release-cleanup file changes.
