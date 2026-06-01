# Design: Pipeline Quality Fixes

## Technical Approach

Three independent but sequenced fixes applied to the same set of 5 MATLAB files. Fix A is applied first to extract the shared path-setup block; Fixes B and C then target the refactored entry scripts alongside the three core functions. All changes are mechanical, behavior-preserving, and verified by `diff` inspection.

## Architecture Decisions

### Decision: Fix A — Extract into `src/config/setup_pseudo_CT_paths.m`

| Option | Tradeoff | Decision |
|--------|----------|----------|
| A1: Keep `[pathp, ~] = fileparts(mfilename('fullpath'))` + `addpath(pathp,'-begin')` in the entry script; pass `root_dir` to the extracted function | Avoids the bootstrap problem (function must be findable on path) | ✅ Chosen |
| A2: Also extract the `pathp` computation into the function | Cleaner single call, but `mfilename` resolves inside `setup_pseudo_CT_paths/`, not the entry script | ❌ Broken — wrong root |

**Function signature**: `function setup_pseudo_CT_paths(root_dir)`

**Call site** in both entry scripts (replaces lines 64-82 / 66-84):

```matlab
[pathp, ~, ~] = fileparts(mfilename('fullpath'));
addpath(fullfile(pathp, 'src', 'config'), '-begin');  % bootstrap: find the helper
setup_pseudo_CT_paths(pathp);
```

The function handles: `addpath(root_dir)`, `genpath` for `src/`, `spm8-r6313/`, `imgaussian/`, `ssh2_v2_m1_r5/`, `vers/`, plus `clear spm_vol_nifti spm_preproc_write8` and `rehash`.

**Rationale**: `src/config/` must be added non-recursively before calling the function so MATLAB can resolve it. The `setup_pseudo_CT_paths` function then adds the full `genpath(fullfile(root_dir, 'src'))` which redundantly includes `config/` again — harmless with `-begin` flag.

### Decision: Fix B — `isstr`→`ischar`, `|`→`||`, `&`→`&&`

**Choice**: Mechanical find-replace across 5 files. Only scalar logical contexts where operands have no side effects.

**Rationale**: `isstr` is a deprecated alias removed in MATLAB R2023a+. `|`/`&` are element-wise operators — in scalar contexts they behave identically to `||`/`&&` but fail to short-circuit, which is a latent performance issue and generates `mlint` warnings.

### Decision: Fix C — `== 0` → `~` for mkdir/rmdir guards

**Choice**: Replace `success == 0` / `mkdir_success == 0` / `remove_success == 0` with `~success` / `~mkdir_success` / `~remove_success`. Only where the return value comes from `mkdir()` or `rmdir()` calls.

**Rationale**: MATLAB `mkdir`/`rmdir` return logical `true`/`false`. Using `~var` is idiomatic MATLAB and avoids the redundant `== 0` comparison. Files outside scope (`pseudo_CT_promote_final_outputs.m`, `nii2dcm_header_copy_vb20_david.m`, `mMR_nii2mu_dicom_blur_david.m`) are deferred.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `src/config/setup_pseudo_CT_paths.m` | **Create** | Shared path-setup function (Fix A) |
| `run_pseudo_CT_local.m` | Modify | Replace L64-82 with 3-line bootstrap + call; Fix B: L149 (`isstr` → `ischar`, `\|` → `\|\|`); Fix C: L197, L259 (`== 0` → `~`) |
| `run_pseudo_CT_launchpad.m` | Modify | Replace L66-84 with 3-line bootstrap + call; Fix B: L213 (`isstr` → `ischar`, `\|` → `\|\|`); Fix C: L104, L158 (`== 0` → `~`) |
| `src/core/atlas_based_attenuation_map.m` | Modify | Fix B: L105, L173 (`\|` → `\|\|`), L149 (`isstr` → `ischar`) |
| `src/core/move_image_2_MNI.m` | Modify | Fix B: L15 (`isstr` → `ischar`) |
| `src/io/convert_dicom_i_2_nii.m` | Modify | Fix B: L11, L37, L61, L63c (`isstr`→`ischar`, `\|`→`\|\|`), L12, L86, L107, L112 (`&`→`&&`); Fix C: L16, L88, L114 (`== 0` → `~`) |

> `L63c` = commented-out line; replaced for consistency.

## Dependencies Between Fixes

```
Fix A (extract path setup) ──→ Fix B (operators) ──→ Fix C (mkdir guards)
       │                            │                     │
       └── changes entry scripts ───┴── same files ───────┘
```

Fix A must be applied first: it rewrites 17 lines in each entry script. Fixes B and C touch different lines within those same files, so they compose cleanly after A is in place. The three core functions (`atlas_based_attenuation_map`, `move_image_2_MNI`, `convert_dicom_i_2_nii`) only receive Fix B and Fix C — no Fix A dependency.

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Manual | Path setup after extraction | Run both entry scripts, verify no `undefined function` errors |
| Manual | Operator fixes | `mlint` each modified file; verify 0 warnings for deprecated `isstr` or element-wise ops |
| Regression | Behavior preservation | Run a single-subject pipeline with a test MPRAGE; `diff` output DICOM + NIfTI against pre-change run |

## Risks & Edge Cases

| Risk | Mitigation |
|------|-----------|
| `setup_pseudo_CT_paths` not on path at call time | Bootstrap with `addpath(fullfile(pathp, 'src', 'config'), '-begin')` before the call |
| Short-circuit `\|\|` changes behavior if operands have side effects | Verified: all replaced `\|` operands are pure boolean expressions (`ischar`, `strcmp`, `length(...)==0`, `isdir`) |
| `convert_dicom_i_2_nii.m` L61: `strcmp(A,'PT') \| strcmp(A,'PET')` → both operands have no side effects | Safe |
| `atlas_based_attenuation_map.m` L253 uses mixed `&&`/`&` in one condition | Noted but out of scope; the `&` operands are scalar and could be `&&` in a future pass |

## Open Questions

- [ ] None — all changes are fully specified and verifiable by diff
