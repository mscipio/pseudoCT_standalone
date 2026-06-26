# Proposal: Pipeline Quality Fixes

## Intent

Eliminate duplicated path-setup code and fix deprecated/incorrect MATLAB operators across the two entry points and three core functions. These are low-risk code-quality improvements that make the codebase idiomatic, reduce drift risk between entry scripts, and remove deprecation warnings in modern MATLAB.

## Scope

### In Scope
- Extract the identical 17-line `addpath`+`clear`+`rehash` block from `run_pseudo_CT_local.m` (lines 64–82) and `run_pseudo_CT_launchpad.m` (lines 66–84) into `src/config/setup_pseudo_CT_paths.m`
- Replace `isstr` → `ischar` in 5 files
- Replace element-wise `|` → `||` (scalar short-circuit OR) in 5 files
- Replace element-wise `&` → `&&` (scalar short-circuit AND) in `convert_dicom_i_2_nii.m` where operands are scalar
- Fix `mkdir_success == 0` / `success == 0` / `remove_success == 0` → `~mkdir_success` / `~success` / `~remove_success` in both entry points and `convert_dicom_i_2_nii.m`

### Out of Scope
- Refactoring the `local_collect_jobs`/`launchpad_collect_jobs` duplication (separate change)
- Adding unit tests (no test framework exists yet)
- Changing any pipeline output or observable behavior
- Updating version strings

## Capabilities

### New Capabilities

None — all fixes are internal refactorings with no new user-facing behavior.

### Modified Capabilities

None — no existing spec-level requirements change. `batch-autodiscovery-observability` is unaffected.

## Approach

1. Create `src/config/setup_pseudo_CT_paths.m` with the shared path-setup logic; call it from both entry scripts (Fix A)
2. In each affected file, perform a single pass replacing `isstr`→`ischar`, `|`→`||`, `&`→`&&` (scalar contexts only), and `== 0`→`~` for `mkdir`/`rmdir` success checks (Fixes B & C)
3. Verify no functional change by running `diff` on each modified file and confirming only the targeted patterns changed

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/config/setup_pseudo_CT_paths.m` | New | Extracted path-setup helper |
| `run_pseudo_CT_local.m` | Modified | Calls helper; operator fixes; mkdir guard |
| `run_pseudo_CT_launchpad.m` | Modified | Calls helper; operator fixes; mkdir guard |
| `src/core/atlas_based_attenuation_map.m` | Modified | `isstr`→`ischar`, `|`→`||` |
| `src/core/move_image_2_MNI.m` | Modified | `isstr`→`ischar` |
| `src/io/convert_dicom_i_2_nii.m` | Modified | `isstr`→`ischar`, `|`→`||`, `&`→`&&`, mkdir guard |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Path setup function not found at runtime (path not set) | Low | Helper lives under `src/config/`, which `genpath` already adds; call happens before `local_collect_jobs` |
| Short-circuit `||`/`&&` changes early-exit behavior where operands had side effects | Low | All replaced operands are pure boolean expressions with no side effects; verified per-line |
| Typo in `ischar` replacement causes runtime error | Low | Mechanical find-replace; `ischar` is the correct modern name for `isstr` |

## Rollback Plan

`git revert` the single commit. No external dependencies, no config changes, no data migrations.

## Dependencies

- MATLAB with SPM8 on path (existing dependency, unchanged)

## Success Criteria

- [ ] Both entry scripts run without errors after extracting `setup_pseudo_CT_paths`
- [ ] Zero occurrences of `isstr` in the 5 target files
- [ ] All scalar `|` replaced by `||` and scalar `&` by `&&` in the target files
- [ ] `mkdir`/`rmdir` success checks use `~var` instead of `var == 0`
- [ ] Pipeline output byte-identical to pre-change run for a test subject