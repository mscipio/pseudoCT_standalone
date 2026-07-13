# Proposal: Entrypoint Divergence Diagnosis

## Intent

Local and Launchpad entrypoints produce very similar but non-identical pseudo-CT results. We need reproducible diagnostic tooling that preserves intermediates and compares paired runs to identify the first divergent artifact. Exploration found `MPRAGE_spm.nii` is identical, `MPRAGE_spm_normalized.nii` diverges, and `MR_PET/tmp/` is absent because cleanup already ran.

## Scope

### In Scope
- Add config/defaults-driven temp preservation: `keep_temp_files = 'No'|'Yes'` in both defaults files; optional `PSEUDOCT_KEEP_TMP=1` override.
- Gate cleanup in `run_pseudo_CT_local.m`, `run_pseudo_CT_launchpad.m`, and cluster-side `rm -rf` in `src/launchpad/batch_pseudo_CT_launchpad.m`.
- Add `scripts/diff_entrypoint_runs.m` to compare same-named local/Launchpad files (`.nii`, `.mat`, DICOM, text/other) with type-appropriate tolerances.

### Out of Scope
- Fixing the compiled Launchpad v2.0 backend or rebuilding it.
- Proving the root cause in this change; this change enables the investigation.
- CI automation for full pipeline comparison.

## Capabilities

### New Capabilities
- `entrypoint-divergence-diagnostics`: Preserve and compare local/Launchpad intermediates to locate the first divergence.

### Modified Capabilities
- None.

## Approach

Use defaults as the primary activation mechanism because the user prefers config activation. Implement `keep_temp_files` in `src/config/defaults_pseudo_CT.m` and `src/config/defaults_pseudo_CT_launchpad.m`; allow `PSEUDOCT_KEEP_TMP` to temporarily override without editing files. Plumb a `keep_tmp` name-value arg into `batch_pseudo_CT_launchpad` so local `MR_PET/tmp/` and Launchpad scratch folders can survive. The comparator reports file presence, first differing matched file, expected differences, and numeric summary metrics.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/config/defaults_pseudo_CT*.m` | Modified | Add `keep_temp_files` setting. |
| `run_pseudo_CT_local.m` | Modified | Skip final `MR_PET/tmp` removal when enabled. |
| `run_pseudo_CT_launchpad.m` | Modified | Skip final `MR_PET/tmp` removal and pass `keep_tmp`. |
| `src/launchpad/batch_pseudo_CT_launchpad.m` | Modified | Gate cluster-side `rm -rf` and intermediate cleanup. |
| `scripts/diff_entrypoint_runs.m` | New | MATLAB comparison report. |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Opaque compiled v2.0 backend | High | Treat Launchpad as black-box output only. |
| Atlas/FreeSurfer/version drift | Medium | Report versions/paths and flag assumptions. |
| False positives from byte comparison | Medium | Use tolerances for numeric image data. |

## Rollback Plan

Set `keep_temp_files = 'No'` or unset `PSEUDOCT_KEEP_TMP`; remove the comparator script and cleanup gates if needed. Default behavior remains cleanup-on-success.

## Dependencies

- MATLAB with bundled SPM8 for NIfTI comparison.
- Re-run both pipelines after enabling temp preservation.

## Success Criteria

- [ ] Defaults can enable temp preservation for both entrypoints.
- [ ] Local, Launchpad local temp, and Launchpad cluster scratch cleanup are all gated.
- [ ] Comparator identifies identical `MPRAGE_spm.nii` and divergent `MPRAGE_spm_normalized.nii` on preserved runs.
- [ ] Default production behavior remains unchanged.
