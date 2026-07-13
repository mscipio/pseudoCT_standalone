# TODO

- Investigate true local MATLAB R2010b compatibility for the FreeSurfer normalization step.
  - Current status: MATLAB code path appears R2010b-compatible, but `mri_normalize` fails when launched from R2010b because it picks up MATLAB 7.11 / MCR `libstdc++.so.6` from the runtime environment.
  - Error seen:
    - `GLIBCXX_3.4.11 not found`
    - offending library path: `/autofs/cluster/matlab/7.11/sys/os/glnxa64/libstdc++.so.6`
  - Likely fix direction: scrub or override `LD_LIBRARY_PATH` (and related runtime library variables if needed) before invoking FreeSurfer binaries from MATLAB R2010b.
  - Reason to revisit: repo-level backward compatibility is incomplete until external native-tool invocation works cleanly from R2010b too.

- Investigate GUI callback compatibility when `PSEUDOCT_SPM_VARIANT=dan`.
  - Current status: `run_pseudo_CT_local` fails during GUI-based MPRAGE selection with:
    - `Too many input arguments.`
    - `Error while evaluating UIControl Callback.`
  - Workaround for now: bypass the GUI and call `run_pseudo_CT_local({...full_dicom_path...})` with an explicit filepath/cell array.
  - Reason to revisit: controlled `spm8-dan` parity testing currently requires bypassing the normal interactive local workflow.

- Investigate a robust way to save the full MATLAB console log for each run into a text file in the final `MR_PET/` output folder.
  - Goal: persist the complete run transcript (warnings, progress messages, external tool output, errors) as a `.txt` artifact alongside the generated pseudo-CT outputs.
  - Reason to revisit: this would make divergence debugging and run-to-run auditing much easier, especially when comparing local vs Launchpad behavior.

- Investigate Launchpad support for denoised NIfTI MPRAGE inputs.
  - User report: when a denoised MPRAGE NIfTI is provided as input to `run_pseudo_CT_launchpad.m`, the program appears to run but stalls / never produces the final pseudo-CT output, even though similar denoised NIfTI inputs work in the older `piano_mMR` workflow and in Tom's version of the tool.
  - Context: users sometimes must denoise noisy MPRAGE images (either automatically with David's MATLAB script or manually on `MPRAGE_spm.nii`) to avoid pseudo-CT leakage outside the head.
  - Question to answer: does the current standalone Launchpad path fully support NIfTI MPRAGE inputs, or did the extraction miss helper logic that existed in the larger legacy `piano_mMR` application?
  - Likely follow-up areas: NIfTI-vs-DICOM input handling in `run_pseudo_CT_launchpad.m`, `convert_dicom_i_2_nii.m`, legacy `piano_mMR` call path, and any denoising-related assumptions in the Launchpad batch flow.
