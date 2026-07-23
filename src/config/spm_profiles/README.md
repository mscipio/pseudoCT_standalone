# Profile Configuration Reference

Each `.m` file in this directory defines a pseudo-CT execution profile.
The filename (without `.m`) becomes the profile name, with underscores
converted to hyphens (e.g., `local_current.m` → `local-current`).

Add a new `.m` file here to create a new profile. The profile selector
and `run_pseudo_CT` will auto-discover it.

## Parameters

### Paths

| Parameter | Type | Description |
|-----------|------|-------------|
| `spm_root` | char | Absolute path to the SPM installation directory. The pipeline uses whatever SPM version is found at this path — no version is enforced. |
| `batch_atlas_path` | char | Absolute path to the Batch_atlas directory containing template NIfTI files (TPM.nii, ch2.nii, Template_*.nii, etc.). All files in this directory are used. |

### Pipeline Parameters

| Parameter | Type | Possible Values | Description |
|-----------|------|-----------------|-------------|
| `recenter` | char | `'Yes'`, `'No'` | Recenter subject before normalization. When `'Yes'`, the subject is recentered in the image volume before the atlas-based segmentation. |
| `zero_background` | char | `'Yes'`, `'No'` | Apply zero-background mask to the attenuation map. When `'Yes'`, voxels outside the head are set to zero using the MPRAGE-derived mask. |
| `cleanup_policy` | char | `'remove_on_success'`, `'keep_on_success'` | What to do with intermediate files (`MR_PET/tmp/`) after successful processing. |
| `bone_enabled` | logical | `true`, `false` | Enable bone reduction in the attenuation map. When `true`, bone voxels are reduced to avoid overestimation. |
| `fwhm` | numeric | `0` or positive mm | FWHM of Gaussian filter applied before registration. `0` disables filtering. |
| `aliasing_default` | numeric | `0`, `1` | Default anti-aliasing correction flag. `0` disables, `1` enables nose/back aliasing correction. Users can override per-subject via CLI. |
| `pca_order` | cell array | See below | Ordered list of PCA backend preferences. The pipeline tries each in order until one succeeds. |
| `runtime_guard` | char | `'supported_matlab'`, `'r2010b_only'`, `'launchpad_opaque'` | Controls MATLAB version validation in preflight. `'supported_matlab'` allows any MATLAB. `'r2010b_only'` blocks non-R2010b (bypassed by entrypoint warning). `'launchpad_opaque'` skips local MATLAB checks. |

### PCA Order Options

| Value | Description |
|-------|-------------|
| `'callable_pca'` | Use MATLAB's built-in `pca` function (Statistics Toolbox) |
| `'repo_legacy'` | Use the repository's `pseudo_ct_princomp_legacy.m` shim |
| `'remote'` | PCA is handled remotely (Launchpad profile only) |

Typical orderings:
- `local-current`: `{'callable_pca'; 'repo_legacy'}` — prefer built-in, fallback to legacy
- `local-near-parity-r2010b`: `{'repo_legacy'; 'callable_pca'}` — prefer legacy for R2010b parity
- `launchpad`: `{'remote'}` — PCA handled on cluster

### Launchpad Settings

These parameters are only used by the `launchpad` profile. Other profiles ignore them.

| Parameter | Type | Description |
|-----------|------|-------------|
| `launchpad_host` | char | SSH hostname for the Launchpad cluster |
| `launchpad_runner` | char | Absolute path to the compiled Launchpad runner script |
| `launchpad_mcr_root` | char | Path to the MCR (MATLAB Compiler Runtime) on the cluster |
| `launchpad_defaults_mat` | char | Path to the defaults `.mat` file for the compiled app |
| `launchpad_backend_mat` | char | Path to the compiled `Pseudo_CT_launchpad` binary |
| `launchpad_batch_templates` | char | Path to the Batch_atlas on the cluster (may differ from local) |
| `launchpad_queue` | char | PBS queue name (e.g., `'p60'`, `'max100'`) |
| `launchpad_scratch` | char | Scratch directory on the cluster for temporary files |
| `launchpad_backend_spm_version` | char | SPM version used by the compiled backend (for provenance only) |
| `launchpad_backend_runtime` | char | Runtime environment on cluster (e.g., `'MCR7.11'`) |

## Example Profile

```matlab
function config = my_custom_profile()
%MY_CUSTOM_PROFILE Configuration for a custom processing profile.

%% === Paths ===
config.spm_root = '/path/to/spm8';
config.batch_atlas_path = '/path/to/Batch_atlas';

%% === Pipeline Parameters ===
config.recenter = 'No';
config.zero_background = 'No';
config.cleanup_policy = 'keep_on_success';
config.bone_enabled = true;
config.fwhm = 0;
config.aliasing_default = 1;
config.pca_order = {'callable_pca'; 'repo_legacy'};
config.runtime_guard = 'supported_matlab';
end
```

## Adding a New Profile

1. Copy an existing `.m` file or use the example above
2. Rename it (filename = profile name, underscores become hyphens)
3. Edit the paths and parameters
4. Run `run_pseudo_CT()` — the new profile appears automatically
