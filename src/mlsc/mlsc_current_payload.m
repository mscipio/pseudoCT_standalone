function mlsc_current_payload(phase, job_manifest_path, resource_manifest_path)
%MLSC_CURRENT_PAYLOAD Compiled-current prepare/compute payload (T002/T003).
%   MLSC_CURRENT_PAYLOAD(PHASE, JOB_MANIFEST_PATH, RESOURCE_MANIFEST_PATH)
%   runs one explicitly selected phase using scalar validated versioned
%   manifests. PHASE is 'prepare' or 'compute' (case-insensitive, fixed
%   argument order).
%
%   T003 ordering contract: preparation runs the bundled alias/recenter code
%   (pseudo_CT_current_prepare) BEFORE the external FreeSurfer boundary.
%   The MLSC shell contract (env -u LD_LIBRARY_PATH ... tcsh -f -c with
%   source /usr/local/freesurfer/nmr-stable53-env) is owned by
%   src/mlsc/mlsc_generate_slurm_script.m. The local/legacy wrapper
%   src/remote/run_normalization_cmd.m and the legacy normalization path
%   are preserved unchanged and are not used by this payload. This payload
%   never normalizes the raw MPRAGE first, never calls run_launchpad_cmd,
%   never submits nested jobs, and never reuses atlas-core remote SSH
%   staging: prepare stops at the bounded handoff, and compute starts only
%   after normalized-output verification. This file contains no GUI,
%   credential, Ganymed/ssh2, scheduler, launchpad, catalog, resolver,
%   legacy-defaults, or addpath roles by construction.
%
%   Prepare writes the bounded handoff mlsc_current_handoff.mat (fixed
%   basename inside the job work_dir; never taken from manifest/handoff
%   content) plus a human-readable mlsc_current_prepare_evidence.txt. The
%   handoff is per-job data consumed only via load() with field-by-field
%   validation: it is never sourced, eval'd, or executed as shell code, and
%   its paths never reach a shell. Controlled basenames/flags:
%   input_selected/normalized_expected are single-row .nii paths without
%   '..', normalized_expected is exactly the derived '_normalized' variant
%   of the selected input, and the normalization-needed gate
%   (needs_normalization vs '_normalized.nii' presence) must be consistent.
%   Compute verifies the normalized output exists before running science.
%
%   Resource authority (T003): the resource manifest identifies the expected
%   current atlas list plus required resource versions/fingerprints, and the
%   payload compares those identities against disk before either phase
%   enters science (prepare or compute); any mismatch fails closed. The
%   manifest locates the current Batch_atlas tree via atlas_dir (must match
%   the job atlas_dir) and declares atlas_list (expected *Atlas*.nii
%   basenames), resource_names/resource_fingerprints (expected identities
%   for ch2.nii, all three batch MATs -- new_segment_batch.mat,
%   dartel_existing_template_batch.mat, create_inverse_warped_batch.mat --
%   Template_1..6.nii, and every listed atlas, as bytes/datenum
%   fingerprints), tpm_fingerprint (expected SPM8 toolbox/Seg/TPM.nii
%   identity, verified via spm('Dir') when SPM is discoverable; otherwise
%   the headless SPM gate fails closed before science), qc_fingerprint
%   (expected bundled hot_map_mpitool_1024.mat identity), and the native
%   evidence contract below. The same physical Batch_atlas directory is
%   allowed, but neither a legacy runner/defaults MAT nor the deployed
%   atlas-local TPM.nii is authoritative: the headless path always uses the
%   explicit SPM toolbox TPM.nii, independent of isdeployed. Evidence files
%   record the verified actual fingerprints.
%
%   Payload-boundary dependency classes (T003 bounded audit from
%   pseudo_CT_current_prepare + pseudo_CT_current_compute, including the
%   one-hop transitives move_image_2_MNI/head_mask_mprage/reduce_bone_segment/
%   quick_fusion_pseudo_ct/toverlay2/pca-resolver actually executed on the
%   payload path; dead/commented/conditional-not-taken branches excluded):
%     A MATLAB/toolbox m-files (toolbox authority, which() must resolve
%       under toolbox/images or toolbox/stats; shadowed/wrong-root fails):
%       nlinfit (Statistics, move_image_2_MNI hist fit), imfill/bwlabel/
%       bwlabeln/imdilate/imerode/imclose (Image Processing, move/mask/
%       compute/reduce paths).
%     B SPM/current MATLAB m-files (SPM/repo/vers/aliasing authority,
%       which() must resolve under the intended root; shadowed/wrong-root
%       fails): spm/spm_jobman/cfg_util (cfg_util must resolve under
%       spmDir/matlabbatch, enforcing main-matlabbatch precedence, no WFU
%       shadowing), spm_vol/spm_read_vols/spm_write_vol/spm_smooth/
%       spm_reslice/spm_get_defaults/spm_run_coreg_estwrite (prepare direct,
%       estwrite via evalc string)/spm_run_coreg_estimate (move_image_2_MNI
%       via evalc string)/spm_matrix/spm_dartel_template/tbx_cfg_dartel,
%       vers overrides spm_vol_nifti/spm_preproc_write8 (must resolve exactly
%       to vers/, never the SPM original), repo helpers move_image_2_MNI/
%       head_mask_mprage/CT_2_att_map/reduce_bone_segment/
%       quick_fusion_pseudo_ct/toverlay2/spm_reslice_david/
%       pseudo_CT_pca_resolver/pseudo_ct_princomp_legacy/pseudo_CT_output/
%       pseudo_CT_write_version_log (must resolve under src/), and the
%       external correct_aliasing facade plus its bundled transitives (must
%       resolve under a correct_aliasing standalone tree, never under
%       repo src or SPM).
%     C native/MEX (SPM Dir authority + manifest evidence, fail-closed):
%       spm_sample_vol/spm_bsplinc/spm_bsplins/spm_slice_vol/spm_conv_vol
%       (.mexa64 under spmDir; slice/conv reachable via vers
%       spm_preproc_write8 decimate/reslice generating rc* consumed by
%       compute).
%       File-exists/which/.mexa64/ELF/mcc-inclusion never proves loadability.
%       Each entry ties relative path + bytes/datenum fingerprint +
%       platform/arch (glnxa64) + MEX type + validation provenance/status in
%       the resource manifest. Missing/wrong-identity/incompatible-arch/
%       missing-evidence fails closed. The manifest validation status is
%       explicitly the pending marker below: production validated-load
%       evidence belongs to T007/Gate A and comes later; this gate never
%       claims validated loadability and never invents validated markers.
%     D external resources already owned by manifest/handoff (atlas list,
%       ch2/batches/Templates/TPM/QC, handoff fields): validated by
%       local_validate_atlas_resources + handoff checks, never duplicated in
%       the code inventory. Excluded from the code gate by design (dead
%       savenifti/spm_create_vol_david branches with write_vol=0, commented
%       imfill/savenifti, interactive-only spm_select, base MATLAB
%       builtins, optional pca with repo_legacy fallback, imgaussian
%       alternative filter, spm_dicom_convert outside the NIfTI payload).
%
%   This payload always runs the explicitly opt-in headless path
%   (default-off for existing local callers): bundled SPM initialization
%   plus in-process noninteractive cfg_util batch execution with explicit
%   current SPM toolbox/Seg/TPM.nii resources, independent of isdeployed.
%   It has no GUI, credential, Ganymed, scheduler, or runtime external
%   MATLAB-code path dependency: no password dialogs, no ssh2/Ganymed
%   calls, no job submission, no profile-file loading, no fwhm/DICOM
%   finalization (config.fwhm stays in local DICOM finalization).
%
%   Job manifest (.mat, scalar struct variable JOB):
%     schema = 'pseudo-CT.mlsc-current-job/v1', manifest_version = 1,
%     input_mprage (existing .nii path), work_dir (existing directory),
%     atlas_dir (atlas/batch template directory),
%     check_aliasing scalar 0/1, recenter_before_normalization ('Yes'/'No'
%     or scalar logical), bone_enabled scalar logical,
%     zero_background ('Yes'/'No').
%   Resource manifest (.mat, scalar struct variable RESOURCES):
%     schema = 'pseudo-CT.mlsc-current-resources/v1',
%     manifest_version = 1, atlas_dir (must match job atlas_dir),
%     atlas_list (cell vector of expected *Atlas*.nii basenames),
%     resource_names/resource_fingerprints (parallel cell vectors covering
%     ch2.nii, the three batch MATs, Template_1..6.nii, and every atlas in
%     atlas_list, each fingerprint a bytes/datenum identity string),
%     tpm_fingerprint/qc_fingerprint (expected bundled SPM toolbox TPM.nii
%     and hot_map_mpitool_1024.mat identities),
%     native_names/native_fingerprints/native_types (parallel cell vectors
%     covering exactly spm_sample_vol.mexa64, spm_bsplinc.mexa64,
%     spm_bsplins.mexa64, spm_slice_vol.mexa64, spm_conv_vol.mexa64 as
%     SPM-Dir-relative paths, bytes/datenum fingerprints, and 'MEX' types;
%     slice/conv reachable via vers spm_preproc_write8 decimate/reslice
%     generating rc* consumed by compute), native_platform/native_arch (both
%     'glnxa64'), native_validation (must equal the explicit pending marker
%     't007-gate-a-pending: existence-only; production loadability evidence
%     comes later'). Actual disk identities must equal the declared
%     expectations before either phase enters science; no legacy
%     runner/defaults MAT, catalog, or resolver fields exist here.
%   Both manifests must be scalar (1x1) structs; anything else fails
%   closed before science.
%
%   Emit contract: compute requires att_map.nii,
%   Fusion_MR_Pseudo_CT_validation.tiff, and Pseudo_CT_AC_Version.txt
%   (written by the shared compute helper) plus normalization evidence and
%   an mlsc_current_output_verification.txt covering the verified
%   normalized input and every required output. Every failure raises
%   (nonzero propagation); no science runs on failed validation.
%
%   Minimum supported MATLAB: R2010b.

if nargin ~= 3
    error('pseudo_CT:MLSCPayloadUsage', ...
        'Usage: mlsc_current_payload(phase, job_manifest_path, resource_manifest_path).');
end
if ~ischar(phase) || size(phase, 1) ~= 1
    error('pseudo_CT:MLSCPayloadManifest', 'Phase must be a single row string.');
end
phase_name = lower(strtrim(phase));
if ~strcmp(phase_name, 'prepare') && ~strcmp(phase_name, 'compute')
    error('pseudo_CT:MLSCPayloadManifest', ...
        'Unknown MLSC current phase: %s (expected prepare or compute).', phase);
end
if ~ischar(job_manifest_path) || size(job_manifest_path, 1) ~= 1 || isempty(strtrim(job_manifest_path))
    error('pseudo_CT:MLSCPayloadManifest', 'Job manifest path must be a non-empty string.');
end
if ~ischar(resource_manifest_path) || size(resource_manifest_path, 1) ~= 1 || isempty(strtrim(resource_manifest_path))
    error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest path must be a non-empty string.');
end
if exist(job_manifest_path, 'file') ~= 2
    error('pseudo_CT:MLSCPayloadManifest', 'Job manifest not found: %s', job_manifest_path);
end
if exist(resource_manifest_path, 'file') ~= 2
    error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest not found: %s', resource_manifest_path);
end

job = local_load_scalar_struct(job_manifest_path, 'job', ...
    'pseudo-CT.mlsc-current-job/v1');
resources = local_load_scalar_struct(resource_manifest_path, 'resources', ...
    'pseudo-CT.mlsc-current-resources/v1');
local_validate_job(job);
local_validate_resources(resources);
if ~strcmp(local_strip_sep(job.atlas_dir), local_strip_sep(resources.atlas_dir))
    error('pseudo_CT:MLSCPayloadManifest', ...
        'Job and resource atlas directories do not match.');
end
atlas_dir = job.atlas_dir;
local_validate_atlas_resources(atlas_dir, resources);
local_validate_code_native_inventory(resources);

% Effective science config assembled from validated manifests only. No
% profile file is loaded here so the deployed payload never depends on
% loose MATLAB code. pca_order matches local-current callable-first order.
config = struct();
config.mode = 'mlsc';
config.implementation = 'current';
config.atlas_root = atlas_dir;
config.spm_root = '';
config.recenter_before_normalization = local_to_yes_no(job.recenter_before_normalization);
config.zero_background = local_to_yes_no(job.zero_background);
config.bone_enabled = logical(job.bone_enabled);
config.pca_order = {'callable_pca'; 'repo_legacy'};
config.headless = true;

output_context = struct('scope', 'mlsc-current');
output_context.headless = true;

if strcmp(phase_name, 'prepare')
    P = job.input_mprage;
    if size(P, 1) ~= 1
        P = P(:)';
    end
    [P_prepared, handoff, early_return, fh] = pseudo_CT_current_prepare( ...
        P, atlas_dir, double(job.check_aliasing), config, output_context, []);
    if ~isempty(fh)
        try
            close(fh);
        catch %#ok<CTCH>
        end
    end
    if early_return
        error('pseudo_CT:MLSCPayloadPrepare', ...
            'Current preparation requested early return; see log for cause.');
    end
    if ~isstruct(handoff) || numel(handoff) ~= 1 || ~isfield(handoff, 'schema')
        error('pseudo_CT:MLSCPayloadPrepare', 'Preparation produced an invalid handoff.');
    end
    handoff_path = fullfile(job.work_dir, 'mlsc_current_handoff.mat');
    handoff.job_manifest = job_manifest_path;
    handoff.resource_manifest = resource_manifest_path;
    save(handoff_path, 'handoff');
    local_write_prepare_evidence(fullfile(job.work_dir, ...
        'mlsc_current_prepare_evidence.txt'), job, handoff, atlas_dir);
    pseudo_CT_output('SUCCESS', output_context, 'MLSC current prepare wrote handoff: %s', handoff_path);
    return;
end

% Compute phase: consume verified normalized input via the bounded handoff.
handoff_path = fullfile(job.work_dir, 'mlsc_current_handoff.mat');
if exist(handoff_path, 'file') ~= 2
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff not found: %s', handoff_path);
end
loaded = load(handoff_path);
if ~isfield(loaded, 'handoff') || ~isstruct(loaded.handoff) || numel(loaded.handoff) ~= 1
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff content is invalid: %s', handoff_path);
end
handoff = loaded.handoff;
if ~isfield(handoff, 'schema') || ~ischar(handoff.schema) || ...
        ~strcmp(handoff.schema, 'pseudo-CT.current-handoff/v1')
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff schema mismatch: %s', handoff_path);
end
if ~isfield(handoff, 'input_selected') || ~ischar(handoff.input_selected) || ...
        size(handoff.input_selected, 1) ~= 1 || isempty(strtrim(handoff.input_selected))
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff input is invalid.');
end
if ~isfield(handoff, 'atlas_dir') || ~ischar(handoff.atlas_dir) || ...
        size(handoff.atlas_dir, 1) ~= 1 || isempty(strtrim(handoff.atlas_dir))
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff atlas directory is invalid.');
end
if ~strcmp(local_strip_sep(handoff.atlas_dir), local_strip_sep(atlas_dir))
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff atlas directory does not match manifests.');
end
if ~isfield(handoff, 'needs_normalization') || ~islogical(handoff.needs_normalization) || ...
        ~isscalar(handoff.needs_normalization)
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff normalization flag is invalid.');
end
if ~isfield(handoff, 'normalized_expected') || ~ischar(handoff.normalized_expected) || ...
        size(handoff.normalized_expected, 1) ~= 1 || isempty(strtrim(handoff.normalized_expected))
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff normalized output is invalid.');
end
% Controlled basenames: single-row .nii paths (optional trailing ',1')
% with no parent-directory traversal. Handoff paths are data only and
% never reach a shell, eval, or source step.
local_require_controlled_nii(handoff.input_selected, 'Handoff input', ...
    'pseudo_CT:MLSCPayloadCompute');
local_require_controlled_nii(handoff.normalized_expected, 'Handoff normalized output', ...
    'pseudo_CT:MLSCPayloadCompute');
if ~isfield(handoff, 'aliasing_effective') || ~islogical(handoff.aliasing_effective) || ...
        ~isscalar(handoff.aliasing_effective)
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff aliasing setting is invalid.');
end
if ~isfield(handoff, 'recenter_effective') || ~islogical(handoff.recenter_effective) || ...
        ~isscalar(handoff.recenter_effective)
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff recenter setting is invalid.');
end
selected_trimmed = strtrim(handoff.input_selected);
expected_trimmed = strtrim(handoff.normalized_expected);
if strcmp(selected_trimmed, expected_trimmed)
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff selected/expected inputs are contradictory.');
end
if isempty(strfind(expected_trimmed, '_normalized'))
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff selected/expected inputs are contradictory.');
end
if ~strcmp(local_derived_normalized(selected_trimmed), expected_trimmed)
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff selected/expected inputs are contradictory.');
end
selected_is_normalized = ~isempty(strfind(selected_trimmed, '_normalized.nii'));
if logical(handoff.needs_normalization)
    if selected_is_normalized
        error('pseudo_CT:MLSCPayloadCompute', 'Handoff selected/expected inputs are contradictory.');
    end
else
    if ~selected_is_normalized
        error('pseudo_CT:MLSCPayloadCompute', 'Handoff selected/expected inputs are contradictory.');
    end
end
job_input_trimmed = strtrim(job.input_mprage);
work_dir_trimmed = strtrim(job.work_dir);
bound_dir = local_bound_workdir(work_dir_trimmed);
selected_resolved = local_resolve_bound_path(selected_trimmed, bound_dir);
original_resolved = local_resolve_bound_path(job_input_trimmed, bound_dir);
corrected_resolved = local_resolve_bound_path(local_corrected_variant(job_input_trimmed), bound_dir);
if isempty(selected_resolved) || isempty(original_resolved) || isempty(corrected_resolved) || ...
        (~strcmp(selected_resolved, original_resolved) && ~strcmp(selected_resolved, corrected_resolved))
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff input does not match current job input.');
end
if logical(handoff.aliasing_effective) ~= logical(job.check_aliasing)
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff aliasing setting does not match current job.');
end
if logical(handoff.recenter_effective) ~= strcmp(config.recenter_before_normalization, 'Yes')
    error('pseudo_CT:MLSCPayloadCompute', 'Handoff recenter setting does not match current job.');
end

if logical(handoff.needs_normalization)
    normalized_input = expected_trimmed;
    if exist(normalized_input, 'file') ~= 2
        error('pseudo_CT:MLSCPayloadCompute', ...
            'Verified normalized input missing: %s', normalized_input);
    end
    P = normalized_input;
else
    P = selected_trimmed;
    if exist(P, 'file') ~= 2
        error('pseudo_CT:MLSCPayloadCompute', 'Handoff input missing: %s', P);
    end
end

Pf = pseudo_CT_current_compute(P, atlas_dir, config, output_context, []);
if ~ischar(Pf) || isempty(strtrim(Pf))
    error('pseudo_CT:MLSCPayloadCompute', 'Current computation produced no outputs.');
end
% Compute writes outputs beside the normalized input directory; verify the
% required attenuation map exists either there or in the manifest work dir.
[comp_dir, ~, ~] = fileparts(deblank(Pf(end, :)));
required_outputs = {fullfile(comp_dir, 'att_map.nii'), ...
    fullfile(comp_dir, 'Fusion_MR_Pseudo_CT_validation.tiff'), ...
    fullfile(comp_dir, 'Pseudo_CT_AC_Version.txt')};
for ii = 1:length(required_outputs)
    if exist(required_outputs{ii}, 'file') ~= 2
        error('pseudo_CT:MLSCPayloadCompute', ...
            'Required current output missing: %s', required_outputs{ii});
    end
end
% Normalization + output-verification evidence: the verified normalized
% input (external FreeSurfer step output) and every required emit-contract
% output, with fingerprints. A failed evidence write fails closed.
local_write_output_verification(fullfile(comp_dir, ...
    'mlsc_current_output_verification.txt'), handoff_path, handoff, P, required_outputs);
if ~strcmp(local_strip_sep(comp_dir), local_strip_sep(job.work_dir))
    pseudo_CT_output('INFO', output_context, 'Compute outputs in: %s', comp_dir);
end
pseudo_CT_output('SUCCESS', output_context, 'MLSC current compute completed.');
return
end

function value = local_load_scalar_struct(manifest_path, variable_name, expected_schema)
loaded = load(manifest_path);
if ~isfield(loaded, variable_name)
    error('pseudo_CT:MLSCPayloadManifest', ...
        'Manifest %s is missing variable %s.', manifest_path, variable_name);
end
value = loaded.(variable_name);
if ~isstruct(value) || numel(value) ~= 1
    error('pseudo_CT:MLSCPayloadManifest', ...
        'Manifest %s variable %s must be one scalar struct.', manifest_path, variable_name);
end
if ~isfield(value, 'schema') || ~ischar(value.schema) || size(value.schema, 1) ~= 1 || ...
        ~strcmp(value.schema, expected_schema)
    error('pseudo_CT:MLSCPayloadManifest', ...
        'Manifest %s has an unexpected schema.', manifest_path);
end
if ~isfield(value, 'manifest_version') || ~isnumeric(value.manifest_version) || ...
        ~isscalar(value.manifest_version) || value.manifest_version ~= 1
    error('pseudo_CT:MLSCPayloadManifest', ...
        'Manifest %s has an unsupported version.', manifest_path);
end
end

function local_validate_job(job)
required = {'input_mprage'; 'work_dir'; 'atlas_dir'; 'check_aliasing'; ...
    'recenter_before_normalization'; 'bone_enabled'; 'zero_background'};
for ii = 1:length(required)
    if ~isfield(job, required{ii})
        error('pseudo_CT:MLSCPayloadManifest', ...
            'Job manifest is missing field %s.', required{ii});
    end
end
if ~ischar(job.input_mprage) || size(job.input_mprage, 1) ~= 1 || isempty(strtrim(job.input_mprage))
    error('pseudo_CT:MLSCPayloadManifest', 'Job input_mprage must be a non-empty string.');
end
local_require_controlled_nii(strtrim(job.input_mprage), 'Job input_mprage', ...
    'pseudo_CT:MLSCPayloadManifest');
if exist(strtrim(job.input_mprage), 'file') ~= 2
    error('pseudo_CT:MLSCPayloadManifest', 'Job input not found: %s', strtrim(job.input_mprage));
end
if ~ischar(job.work_dir) || size(job.work_dir, 1) ~= 1 || isempty(strtrim(job.work_dir))
    error('pseudo_CT:MLSCPayloadManifest', 'Job work_dir must be a non-empty string.');
end
local_reject_traversal(strtrim(job.work_dir), 'Job work_dir');
if exist(strtrim(job.work_dir), 'dir') ~= 7
    error('pseudo_CT:MLSCPayloadManifest', 'Job work directory not found: %s', strtrim(job.work_dir));
end
if ~ischar(job.atlas_dir) || size(job.atlas_dir, 1) ~= 1 || isempty(strtrim(job.atlas_dir))
    error('pseudo_CT:MLSCPayloadManifest', 'Job atlas_dir must be a non-empty string.');
end
local_reject_traversal(strtrim(job.atlas_dir), 'Job atlas_dir');
if exist(strtrim(job.atlas_dir), 'dir') ~= 7
    error('pseudo_CT:MLSCPayloadManifest', 'Job atlas directory not found: %s', strtrim(job.atlas_dir));
end
if ~(isnumeric(job.check_aliasing) || islogical(job.check_aliasing)) || ...
        ~isscalar(job.check_aliasing) || ~ismember(double(job.check_aliasing), [0 1])
    error('pseudo_CT:MLSCPayloadManifest', 'Job check_aliasing must be scalar 0 or 1.');
end
local_validate_yes_no(job.recenter_before_normalization, 'recenter_before_normalization');
local_validate_yes_no(job.zero_background, 'zero_background');
if ~(islogical(job.bone_enabled) || isnumeric(job.bone_enabled)) || ...
        ~isscalar(job.bone_enabled) || ~ismember(double(job.bone_enabled), [0 1])
    error('pseudo_CT:MLSCPayloadManifest', 'Job bone_enabled must be scalar logical 0 or 1.');
end
end

function local_validate_resources(resources)
if ~isfield(resources, 'atlas_dir')
    error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest is missing atlas_dir.');
end
if ~ischar(resources.atlas_dir) || size(resources.atlas_dir, 1) ~= 1 || ...
        isempty(strtrim(resources.atlas_dir))
    error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas_dir must be a non-empty string.');
end
if exist(strtrim(resources.atlas_dir), 'dir') ~= 7
    error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas directory not found: %s', strtrim(resources.atlas_dir));
end
if ~isfield(resources, 'atlas_list')
    error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest is missing atlas_list.');
end
if ~isfield(resources, 'resource_names')
    error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest is missing resource_names.');
end
if ~isfield(resources, 'resource_fingerprints')
    error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest is missing resource_fingerprints.');
end
if ~isfield(resources, 'tpm_fingerprint')
    error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest is missing tpm_fingerprint.');
end
if ~isfield(resources, 'qc_fingerprint')
    error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest is missing qc_fingerprint.');
end
if ~isfield(resources, 'native_names')
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource manifest is missing native_names.');
end
if ~isfield(resources, 'native_fingerprints')
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource manifest is missing native_fingerprints.');
end
if ~isfield(resources, 'native_types')
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource manifest is missing native_types.');
end
if ~isfield(resources, 'native_platform')
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource manifest is missing native_platform.');
end
if ~isfield(resources, 'native_arch')
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource manifest is missing native_arch.');
end
if ~isfield(resources, 'native_validation')
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource manifest is missing native_validation.');
end
local_require_atlas_list(resources.atlas_list);
local_require_resource_maps(resources.resource_names, resources.resource_fingerprints, ...
    resources.atlas_list);
local_require_fingerprint_string(resources.tpm_fingerprint, 'tpm_fingerprint');
local_require_fingerprint_string(resources.qc_fingerprint, 'qc_fingerprint');
local_require_native_manifest(resources);
end

function local_validate_atlas_resources(atlas_dir, resources)
% T003 resource authority: compare manifest-declared expected identities
% against disk before either phase enters science; any mismatch fails
% closed. Covers the expected atlas list, ch2.nii, all three batch MATs,
% Template_1..6.nii, plus the bundled SPM8 toolbox/Seg/TPM.nii and the
% bundled hot_map_mpitool_1024.mat. The same physical Batch_atlas directory
% is allowed, but no legacy runner/defaults MAT is consulted here and the
% deployed atlas-local TPM.nii is never authoritative (the headless path
% always uses the explicit SPM toolbox TPM.nii, independent of isdeployed).
fixed_here = local_fixed_resource_names();
for ii = 1:length(fixed_here)
    if exist(fullfile(atlas_dir, fixed_here{ii}), 'file') ~= 2
        error('pseudo_CT:MLSCPayloadResourceMismatch', ...
            'Atlas resource missing: %s', fullfile(atlas_dir, fixed_here{ii}));
    end
end
atlases = dir(fullfile(atlas_dir, '*Atlas*.nii'));
if isempty(atlases)
    error('pseudo_CT:MLSCPayloadResourceMismatch', 'Atlas resource missing: *Atlas*.nii in %s', atlas_dir);
end
for ii = 1:length(atlases)
    if ~ischar(atlases(ii).name) || isempty(strtrim(atlases(ii).name)) || ...
            ~isempty(strfind(atlases(ii).name, '..'))
        error('pseudo_CT:MLSCPayloadResourceMismatch', 'Atlas resource name is invalid in %s', atlas_dir);
    end
end
actual_atlases = {};
for ii = 1:length(atlases)
    actual_atlases{end + 1, 1} = atlases(ii).name; %#ok<AGROW>
end
expected_atlases = resources.atlas_list(:);
actual_sorted = sort(actual_atlases);
expected_sorted = sort(expected_atlases);
if length(actual_sorted) ~= length(expected_sorted)
    error('pseudo_CT:MLSCPayloadResourceMismatch', ...
        'Atlas list mismatch in %s (expected %d, found %d).', atlas_dir, ...
        length(expected_sorted), length(actual_sorted));
end
for ii = 1:length(expected_sorted)
    if ~strcmp(actual_sorted{ii}, expected_sorted{ii})
        error('pseudo_CT:MLSCPayloadResourceMismatch', ...
            'Atlas list mismatch in %s (expected %s).', atlas_dir, expected_sorted{ii});
    end
end
names_here = resources.resource_names(:);
fps_here = resources.resource_fingerprints(:);
for ii = 1:length(names_here)
    actual_fp = local_fingerprint(fullfile(atlas_dir, names_here{ii}));
    if ~strcmp(actual_fp, strtrim(fps_here{ii}))
        error('pseudo_CT:MLSCPayloadResourceMismatch', ...
            'Resource mismatch: %s', fullfile(atlas_dir, names_here{ii}));
    end
end
% Bundled SPM8 tissue priors: authoritative only via the SPM toolbox tree,
% never via an atlas-local TPM.nii. When SPM is discoverable the identity
% must match now (fail closed before expensive work); otherwise the
% headless/code inventory gate fails closed before any science.
if exist('spm', 'file') == 2
    tpm_path = '';
    try
        tpm_path = fullfile(spm('Dir'), 'toolbox', 'Seg', 'TPM.nii');
    catch
        tpm_path = '';
    end
    if isempty(tpm_path)
        error('pseudo_CT:MLSCPayloadResourceMismatch', 'SPM toolbox location is unavailable.');
    end
    if exist(tpm_path, 'file') ~= 2
        error('pseudo_CT:MLSCPayloadResourceMismatch', ...
            'SPM resource missing: %s', tpm_path);
    end
    if ~strcmp(local_fingerprint(tpm_path), strtrim(resources.tpm_fingerprint))
        error('pseudo_CT:MLSCPayloadResourceMismatch', ...
            'Resource mismatch: %s', tpm_path);
    end
end
% Bundled QC colormap for quick_fusion headless output.
hot_map_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'qc', 'hot_map_mpitool_1024.mat');
if exist(hot_map_path, 'file') ~= 2
    error('pseudo_CT:MLSCPayloadResourceMismatch', ...
        'QC resource missing: %s', hot_map_path);
end
if ~strcmp(local_fingerprint(hot_map_path), strtrim(resources.qc_fingerprint))
    error('pseudo_CT:MLSCPayloadResourceMismatch', ...
        'Resource mismatch: %s', hot_map_path);
end
end

function local_validate_code_native_inventory(resources)
% Payload-boundary bundled code/native inventory (T003).
% Bounded audit roots: pseudo_CT_current_prepare + pseudo_CT_current_compute
% plus the one-hop transitives actually executed on the payload path
% (move_image_2_MNI, head_mask_mprage, reduce_bone_segment,
% quick_fusion_pseudo_ct/toverlay2/spm_reslice_david, pca-resolver chain).
% Runs before either shared helper is entered; any failure raises before
% science with no side effects (no handoff/evidence written by the caller,
% which validates first). Categories:
%   A toolbox m-files (toolbox authority), B SPM/repo/vers/aliasing m-files
%   (intended-root authority, shadowed/wrong-root rejected), C natives
%   (SPM-Dir files + manifest evidence, existence never claims loadability;
%   production validated-load evidence belongs to T007/Gate A and comes
%   later), D resources already owned by manifest/handoff (not duplicated
%   here). No catalog, no resolver, no orchestration, no MCR_ROOT change.
if ~isstruct(resources) || numel(resources) ~= 1
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Native inventory requires the scalar resource manifest.');
end
repo_root_here = fileparts(fileparts(fileparts(mfilename('fullpath'))));
src_dir_here = fullfile(repo_root_here, 'src');
vers_dir_here = fullfile(repo_root_here, 'vers');
spm_dir_here = '';
try
    if exist('spm', 'file') == 2
        spm_dir_here = spm('Dir');
    end
catch
    spm_dir_here = '';
end
if isempty(spm_dir_here) || ~ischar(spm_dir_here)
    error('pseudo_CT:MLSCPayloadDependency', 'Bundled code/native dependency missing: spm (SPM Dir undiscoverable).');
end
spm_batch_dir_here = fullfile(spm_dir_here, 'matlabbatch');
% Class A: toolbox authority (which() under toolbox/images or toolbox/stats).
toolbox_images_here = {'imfill'; 'bwlabel'; 'bwlabeln'; 'imdilate'; 'imerode'; 'imclose'};
for ii = 1:length(toolbox_images_here)
    local_require_toolbox_root(toolbox_images_here{ii}, 'toolbox/images');
end
local_require_toolbox_root('nlinfit', 'toolbox/stats');
% Class B/SPM: SPM-Dir authority (cfg_util additionally requires the main
% matlabbatch tree, rejecting WFU shadowing per setup_pseudo_CT_paths).
spm_plain_here = {'spm'; 'spm_jobman'; 'spm_vol'; 'spm_read_vols'; ...
    'spm_write_vol'; 'spm_smooth'; 'spm_reslice'; 'spm_get_defaults'; ...
    'spm_run_coreg_estwrite'; 'spm_run_coreg_estimate'; 'spm_matrix'; ...
    'spm_dartel_template'; 'tbx_cfg_dartel'};
for ii = 1:length(spm_plain_here)
    local_require_spm_root(spm_plain_here{ii}, spm_dir_here);
end
local_require_spm_root('cfg_util', spm_batch_dir_here);
% Class B/vers: exact vers authority (never the SPM original).
vers_here = {'spm_vol_nifti'; 'spm_preproc_write8'};
for ii = 1:length(vers_here)
    local_require_exact_file(vers_here{ii}, fullfile(vers_dir_here, [vers_here{ii} '.m']));
end
% Class B/repo: src authority for bundled current helpers.
repo_here = {'move_image_2_MNI'; 'head_mask_mprage'; 'CT_2_att_map'; ...
    'reduce_bone_segment'; 'quick_fusion_pseudo_ct'; 'toverlay2'; ...
    'spm_reslice_david'; 'pseudo_CT_pca_resolver'; ...
    'pseudo_ct_princomp_legacy'; 'pseudo_CT_output'; ...
    'pseudo_CT_write_version_log'};
for ii = 1:length(repo_here)
    local_require_src_root(repo_here{ii}, src_dir_here);
end
% Class B/aliasing: external standalone authority (never repo src or SPM).
local_require_aliasing_root('correct_aliasing', src_dir_here, spm_dir_here);
% Class C: native evidence + identity against SPM Dir (fail-closed; existence
% is not loadability; validated-load proof comes in T007/Gate A).
local_validate_native_inventory(resources, spm_dir_here);
end

function local_require_toolbox_root(name_here, toolbox_fragment)
if exist(name_here, 'file') == 0 && exist(name_here, 'builtin') == 0
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency missing: %s', name_here);
end
resolved_here = which(name_here);
if isempty(resolved_here) || isempty(strfind(resolved_here, toolbox_fragment))
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency wrong root: %s (resolved %s)', name_here, resolved_here);
end
end

function local_require_spm_root(name_here, expected_root_here)
if exist(name_here, 'file') == 0 && exist(name_here, 'builtin') == 0
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency missing: %s', name_here);
end
resolved_here = which(name_here);
if isempty(resolved_here) || isempty(strfind(resolved_here, local_strip_sep(expected_root_here)))
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency wrong root: %s (resolved %s)', name_here, resolved_here);
end
end

function local_require_exact_file(name_here, expected_path_here)
if exist(name_here, 'file') == 0
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency missing: %s', name_here);
end
resolved_here = which(name_here);
if isempty(resolved_here) || ~strcmp(resolved_here, expected_path_here)
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency wrong root: %s (resolved %s)', name_here, resolved_here);
end
end

function local_require_src_root(name_here, src_dir_here)
if exist(name_here, 'file') == 0
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency missing: %s', name_here);
end
resolved_here = which(name_here);
if isempty(resolved_here) || isempty(strfind(resolved_here, local_strip_sep(src_dir_here)))
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency wrong root: %s (resolved %s)', name_here, resolved_here);
end
end

function local_require_aliasing_root(name_here, src_dir_here, spm_dir_here)
if exist(name_here, 'file') == 0
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency missing: %s', name_here);
end
resolved_here = which(name_here);
if isempty(resolved_here) || isempty(strfind(resolved_here, 'correct_aliasing'))
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency wrong root: %s (resolved %s)', name_here, resolved_here);
end
if ~isempty(strfind(resolved_here, local_strip_sep(src_dir_here)))
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency wrong root: %s (resolved %s)', name_here, resolved_here);
end
if ~isempty(strfind(resolved_here, local_strip_sep(spm_dir_here)))
    error('pseudo_CT:MLSCPayloadDependency', ...
        'Bundled code/native dependency wrong root: %s (resolved %s)', name_here, resolved_here);
end
end

function local_require_native_manifest(resources)
% Manifest-side shape checks for the C native contract (identity evidence
% lives in the manifest; file/identity/arch checks run in
% local_validate_native_inventory before either helper). The validation
% status must be exactly the T007-pending marker: production
% validated-load evidence comes later and is never claimed or invented here.
if ~iscell(resources.native_names) || ~iscell(resources.native_fingerprints) || ...
        ~iscell(resources.native_types)
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native names/fingerprints/types must be cell vectors.');
end
if ~ischar(resources.native_platform) || size(resources.native_platform, 1) ~= 1 || ...
        isempty(strtrim(resources.native_platform))
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native_platform must be a non-empty string.');
end
if ~ischar(resources.native_arch) || size(resources.native_arch, 1) ~= 1 || ...
        isempty(strtrim(resources.native_arch))
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native_arch must be a non-empty string.');
end
if ~ischar(resources.native_validation) || size(resources.native_validation, 1) ~= 1 || ...
        isempty(strtrim(resources.native_validation))
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native_validation must be a non-empty string.');
end
if numel(resources.native_names) ~= numel(resources.native_fingerprints) || ...
        numel(resources.native_names) ~= numel(resources.native_types)
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native names/fingerprints/types length mismatch.');
end
if isempty(resources.native_names)
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native inventory must be non-empty.');
end
[m_names_here, n_names_here] = size(resources.native_names);
[m_fps_here, n_fps_here] = size(resources.native_fingerprints);
[m_types_here, n_types_here] = size(resources.native_types);
if ~((m_names_here >= 1 && n_names_here == 1) || (m_names_here == 1 && n_names_here >= 1))
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native_names must be a cell vector.');
end
if ~((m_fps_here >= 1 && n_fps_here == 1) || (m_fps_here == 1 && n_fps_here >= 1))
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native_fingerprints must be a cell vector.');
end
if ~((m_types_here >= 1 && n_types_here == 1) || (m_types_here == 1 && n_types_here >= 1))
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native_types must be a cell vector.');
end
expected_natives_here = {'spm_bsplinc.mexa64'; 'spm_bsplins.mexa64'; 'spm_conv_vol.mexa64'; 'spm_sample_vol.mexa64'; 'spm_slice_vol.mexa64'};
actual_sorted_here = sort(resources.native_names(:));
expected_sorted_here = sort(expected_natives_here);
if length(actual_sorted_here) ~= length(expected_sorted_here)
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native inventory must cover exactly the required MEX set.');
end
for ii = 1:length(expected_sorted_here)
    if ~strcmp(actual_sorted_here{ii}, expected_sorted_here{ii})
        error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native inventory must cover exactly the required MEX set.');
    end
end
for ii = 1:numel(resources.native_names)
    entry_here = resources.native_names{ii};
    if ~ischar(entry_here) || size(entry_here, 1) ~= 1 || isempty(strtrim(entry_here))
        error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native names must be non-empty strings.');
    end
    trimmed_here = strtrim(entry_here);
    if ~isempty(strfind(trimmed_here, '..')) || ~isempty(strfind(trimmed_here, '/')) || ...
            ~isempty(strfind(trimmed_here, char(92)))
        error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native name is not a controlled basename: %s', trimmed_here);
    end
    if length(trimmed_here) < 8 || ~strcmp(trimmed_here(end-6:end), '.mexa64')
        error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native names must reference .mexa64 files: %s', trimmed_here);
    end
    local_require_fingerprint_string(resources.native_fingerprints{ii}, 'native_fingerprints');
    type_here = resources.native_types{ii};
    if ~ischar(type_here) || size(type_here, 1) ~= 1 || ~strcmp(strtrim(type_here), 'MEX')
        error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native types must be MEX: %s', trimmed_here);
    end
end
if ~strcmp(strtrim(resources.native_platform), 'glnxa64')
    error('pseudo_CT:MLSCPayloadNativeMismatch', 'Resource native_platform is incompatible: %s', strtrim(resources.native_platform));
end
if ~strcmp(strtrim(resources.native_arch), 'glnxa64')
    error('pseudo_CT:MLSCPayloadNativeMismatch', 'Resource native_arch is incompatible: %s', strtrim(resources.native_arch));
end
if ~strcmp(strtrim(resources.native_validation), local_native_pending_marker())
    error('pseudo_CT:MLSCPayloadNativeEvidence', 'Resource native_validation is invalid (expected T007-pending marker).');
end
end

function marker = local_native_pending_marker()
marker = 't007-gate-a-pending: existence-only; production loadability evidence comes later';
end

function local_validate_native_inventory(resources, spm_dir_here)
% Class C disk/identity checks (fail-closed; existence is not loadability).
% Each manifest entry resolves to fullfile(spmDir, relative .mexa64 path);
% the which() logical name must resolve to exactly that authoritative file
% (directory-boundary-aware canonical equality, not substring): a
% higher-priority shadow or subdirectory alternate never matches even when
% it contains the SPM Dir as a substring. The bytes/datenum fingerprint of
% the authoritative file must match, so the declared identity is bound to
% the resolved executable, and the manifest platform/arch must equal the
% host arch. Missing/wrong-identity/incompatible-arch/missing-evidence all
% fail before either helper. Validated-load proof is explicitly deferred to
% T007/Gate A.
names_here = resources.native_names(:);
fps_here = resources.native_fingerprints(:);
for ii = 1:length(names_here)
    rel_here = strtrim(names_here{ii});
    full_here = fullfile(spm_dir_here, rel_here);
    if exist(full_here, 'file') == 0
        error('pseudo_CT:MLSCPayloadNativeMismatch', 'Native dependency missing: %s', full_here);
    end
    [~, logical_here, ~] = fileparts(rel_here);
    resolved_here = which(logical_here);
    if isempty(resolved_here) || ...
            ~strcmp(local_canonical_path(resolved_here), local_canonical_path(full_here))
        error('pseudo_CT:MLSCPayloadNativeMismatch', 'Native dependency wrong root: %s (resolved %s)', logical_here, resolved_here);
    end
    if ~strcmp(local_fingerprint(full_here), strtrim(fps_here{ii}))
        error('pseudo_CT:MLSCPayloadNativeMismatch', 'Native mismatch: %s', full_here);
    end
end
host_arch_here = '';
try
    host_arch_here = computer('arch');
catch
    host_arch_here = '';
end
if isempty(host_arch_here) || ~strcmp(host_arch_here, strtrim(resources.native_arch)) || ...
        ~strcmp(host_arch_here, strtrim(resources.native_platform))
    error('pseudo_CT:MLSCPayloadNativeMismatch', 'Native architecture mismatch (host %s vs manifest %s/%s).', host_arch_here, strtrim(resources.native_platform), strtrim(resources.native_arch));
end
end

function fixed = local_fixed_resource_names()
fixed = {'ch2.nii'; 'new_segment_batch.mat'; ...
    'dartel_existing_template_batch.mat'; 'create_inverse_warped_batch.mat'; ...
    'Template_1.nii'; 'Template_2.nii'; 'Template_3.nii'; ...
    'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'};
end

function local_require_atlas_list(atlas_list)
if ~iscell(atlas_list) || isempty(atlas_list)
    error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas_list must be a non-empty cell vector.');
end
[m_list, n_list] = size(atlas_list);
if ~((m_list >= 1 && n_list == 1) || (m_list == 1 && n_list >= 1))
    error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas_list must be a cell vector.');
end
for ii = 1:numel(atlas_list)
    entry = atlas_list{ii};
    if ~ischar(entry) || size(entry, 1) ~= 1 || isempty(strtrim(entry))
        error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas_list entries must be non-empty strings.');
    end
    trimmed = strtrim(entry);
    if ~isempty(strfind(trimmed, '..')) || ~isempty(strfind(trimmed, '/')) || ...
            ~isempty(strfind(trimmed, char(92)))
        error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas_list entry is not a controlled basename: %s', trimmed);
    end
    if length(trimmed) < 5 || ~strcmp(lower(trimmed(end-3:end)), '.nii')
        error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas_list entries must reference .nii files: %s', trimmed);
    end
    if isempty(strfind(trimmed, 'Atlas'))
        error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas_list entries must identify atlas files: %s', trimmed);
    end
end
for ii = 1:numel(atlas_list)
    for jj = ii + 1:numel(atlas_list)
        if strcmp(strtrim(atlas_list{ii}), strtrim(atlas_list{jj}))
            error('pseudo_CT:MLSCPayloadManifest', 'Resource atlas_list contains a duplicate: %s', strtrim(atlas_list{ii}));
        end
    end
end
end

function local_require_resource_maps(names_in, fps_in, atlas_list)
if ~iscell(names_in) || ~iscell(fps_in) || isempty(names_in) || isempty(fps_in)
    error('pseudo_CT:MLSCPayloadManifest', 'Resource names/fingerprints must be non-empty cell vectors.');
end
[m_names, n_names] = size(names_in);
[m_fps, n_fps] = size(fps_in);
if ~((m_names >= 1 && n_names == 1) || (m_names == 1 && n_names >= 1))
    error('pseudo_CT:MLSCPayloadManifest', 'Resource names must be a cell vector.');
end
if ~((m_fps >= 1 && n_fps == 1) || (m_fps == 1 && n_fps >= 1))
    error('pseudo_CT:MLSCPayloadManifest', 'Resource fingerprints must be a cell vector.');
end
if numel(names_in) ~= numel(fps_in)
    error('pseudo_CT:MLSCPayloadManifest', 'Resource names/fingerprints length mismatch.');
end
for ii = 1:numel(names_in)
    entry = names_in{ii};
    if ~ischar(entry) || size(entry, 1) ~= 1 || isempty(strtrim(entry))
        error('pseudo_CT:MLSCPayloadManifest', 'Resource names must be non-empty strings.');
    end
    trimmed = strtrim(entry);
    if ~isempty(strfind(trimmed, '..')) || ~isempty(strfind(trimmed, '/')) || ...
            ~isempty(strfind(trimmed, char(92)))
        error('pseudo_CT:MLSCPayloadManifest', 'Resource name is not a controlled basename: %s', trimmed);
    end
    lowered = lower(trimmed);
    if length(trimmed) < 5 || (~strcmp(lowered(end-3:end), '.nii') && ~strcmp(lowered(end-3:end), '.mat'))
        error('pseudo_CT:MLSCPayloadManifest', 'Resource names must reference .nii/.mat files: %s', trimmed);
    end
    local_require_fingerprint_string(fps_in{ii}, 'resource_fingerprints');
end
for ii = 1:numel(names_in)
    for jj = ii + 1:numel(names_in)
        if strcmp(strtrim(names_in{ii}), strtrim(names_in{jj}))
            error('pseudo_CT:MLSCPayloadManifest', 'Resource names contain a duplicate: %s', strtrim(names_in{ii}));
        end
    end
end
fixed_here = local_fixed_resource_names();
for ii = 1:length(fixed_here)
    if local_find_name(names_in, fixed_here{ii}) == 0
        error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest is missing required resource: %s', fixed_here{ii});
    end
end
for ii = 1:numel(atlas_list)
    if local_find_name(names_in, strtrim(atlas_list{ii})) == 0
        error('pseudo_CT:MLSCPayloadManifest', 'Resource manifest is missing listed atlas identity: %s', strtrim(atlas_list{ii}));
    end
end
if numel(names_in) ~= length(fixed_here) + numel(atlas_list)
    error('pseudo_CT:MLSCPayloadManifest', 'Resource names must cover exactly the fixed resources plus atlas_list.');
end
end

function local_require_fingerprint_string(fp_in, label)
if ~ischar(fp_in) || size(fp_in, 1) ~= 1 || isempty(strtrim(fp_in))
    error('pseudo_CT:MLSCPayloadManifest', 'Resource %s must be a non-empty fingerprint string.', label);
end
trimmed = strtrim(fp_in);
if isempty(strfind(trimmed, 'bytes=')) || isempty(strfind(trimmed, 'datenum='))
    error('pseudo_CT:MLSCPayloadManifest', 'Resource %s has an invalid fingerprint identity.', label);
end
end

function idx = local_find_name(names_in, target)
idx = 0;
for kk = 1:numel(names_in)
    if strcmp(strtrim(names_in{kk}), strtrim(target))
        idx = kk;
        return;
    end
end
end

function local_validate_yes_no(value, field_name)
ok = false;
if ischar(value) && size(value, 1) == 1
    trimmed = strtrim(value);
    ok = strcmp(trimmed, 'Yes') || strcmp(trimmed, 'No');
elseif (islogical(value) || isnumeric(value)) && isscalar(value) && isfinite(double(value)) && ...
        ismember(double(value), [0 1])
    ok = true;
end
if ~ok
    error('pseudo_CT:MLSCPayloadManifest', ...
        'Job %s must be Yes/No or scalar logical 0 or 1.', field_name);
end
end

function text = local_to_yes_no(value)
if ischar(value) && size(value, 1) == 1
    trimmed = strtrim(value);
    if strcmp(trimmed, 'Yes') || strcmp(trimmed, 'No')
        text = trimmed;
        return;
    end
end
if (islogical(value) || isnumeric(value)) && isscalar(value) && isfinite(double(value))
    if double(value) == 1
        text = 'Yes';
        return;
    end
    if double(value) == 0
        text = 'No';
        return;
    end
end
error('pseudo_CT:MLSCPayloadManifest', 'Yes/No value is invalid.');
end

function expected = local_derived_normalized(selected)
expected = '';
if isempty(selected) || ~ischar(selected)
    return;
end
[pathn, namen, extn] = fileparts(selected);
if length(extn) >= 2 && strcmp(extn(end-1:end), ',1')
    extn = extn(1:end-2);
end
if isempty(extn)
    extn = '.nii';
end
expected = fullfile(pathn, [namen, '_normalized', extn]);
end

function variant = local_corrected_variant(job_input)
variant = job_input;
if isempty(job_input) || ~ischar(job_input)
    return;
end
[path_in, name_in, ext_in] = fileparts(job_input);
variant = fullfile(path_in, [name_in, '_corrected', ext_in]);
end

function value = local_strip_sep(value)
value = strtrim(value);
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end

function text = local_canonical_path(path_text)
% Directory-boundary-aware canonical form for exact executable binding
% (R2010b-safe): normalize separators, strip trailing separators, collapse
% duplicate separators. Exact strcmp on this form (not substring) binds the
% resolved which() executable to the declared authoritative file, so a
% higher-priority shadow or subdirectory alternate never matches.
if ~ischar(path_text)
    text = '';
    return;
end
text = strtrim(path_text);
if isempty(text)
    return;
end
text(text == char(92)) = '/';
collapsed = '';
prev_sep = false;
for kk = 1:length(text)
    is_sep = (text(kk) == '/');
    if is_sep && prev_sep
        continue;
    end
    collapsed(end + 1) = text(kk); %#ok<AGROW>
    prev_sep = is_sep;
end
text = collapsed;
while length(text) > 1 && text(end) == '/'
    text(end) = '';
end
end

function bound = local_bound_workdir(work_dir_text)
%LOCAL_BOUND_WORKDIR Explicit bound work directory for handoff identity.
%   Resolves the job work_dir to one canonical absolute directory used to
%   bind relative manifest/handoff paths. Absolute work dirs canonicalize
%   directly; relative work dirs (including '.') join explicitly once with
%   pwd and then canonicalize, so per-path incidental-cwd reliance is
%   avoided. Any '..', empty, or unresolvable work dir fails closed ('').
%   R2010b only; string normalization only via local_canonical_path plus
%   local_collapse_dots (no symlink resolution, no fallback).
bound = '';
if ~ischar(work_dir_text) || size(work_dir_text, 1) ~= 1
    return;
end
trimmed = strtrim(work_dir_text);
if isempty(trimmed)
    return;
end
if ~isempty(strfind(trimmed, '..'))
    return;
end
canon = local_canonical_path(trimmed);
if isempty(canon)
    return;
end
if canon(1) == '/'
    collapsed = local_collapse_dots(canon);
    if isempty(collapsed)
        return;
    end
    bound = collapsed;
    return;
end
pwd_text = '';
try
    pwd_text = pwd;
catch %#ok<CTCH>
    return;
end
if ~ischar(pwd_text) || isempty(strtrim(pwd_text))
    return;
end
pwd_canon = local_canonical_path(pwd_text);
if isempty(pwd_canon)
    return;
end
joined = fullfile(pwd_canon, canon);
joined_canon = local_canonical_path(joined);
collapsed = local_collapse_dots(joined_canon);
if isempty(collapsed)
    return;
end
bound = collapsed;
end

function resolved = local_resolve_bound_path(path_text, bound_dir)
%LOCAL_RESOLVE_BOUND_PATH Canonical identity within the bound work dir.
%   Absolute handoff/manifest paths canonicalize directly; relative paths
%   join explicitly with the bound work dir (never incidental cwd per
%   path). Any '..', empty, unresolvable, or unbound-relative path fails
%   closed (''). Exact strcmp on the result proves dir+basename identity:
%   same-basename different-dir never matches, wrong corrected basename
%   never matches. R2010b only.
resolved = '';
if ~ischar(path_text) || size(path_text, 1) ~= 1
    return;
end
trimmed = strtrim(path_text);
if isempty(trimmed)
    return;
end
if ~isempty(strfind(trimmed, '..'))
    return;
end
canon = local_canonical_path(trimmed);
if isempty(canon)
    return;
end
if canon(1) == '/'
    collapsed = local_collapse_dots(canon);
    if isempty(collapsed)
        return;
    end
    resolved = collapsed;
    return;
end
if ~ischar(bound_dir) || isempty(bound_dir)
    return;
end
if ~isempty(strfind(bound_dir, '..'))
    return;
end
joined = fullfile(strtrim(bound_dir), canon);
joined_canon = local_canonical_path(joined);
collapsed = local_collapse_dots(joined_canon);
if isempty(collapsed)
    return;
end
resolved = collapsed;
end

function collapsed = local_collapse_dots(path_text)
%LOCAL_COLLAPSE_DOTS Collapse '.' segments without resolving '..'.
%   Any '..' segment fails closed ('') since controlled paths never
%   contain traversal. R2010b only.
collapsed = '';
if ~ischar(path_text) || size(path_text, 1) ~= 1
    return;
end
trimmed = strtrim(path_text);
if isempty(trimmed)
    return;
end
is_abs = (trimmed(1) == '/');
tokens = {};
start_idx = 1;
n = length(trimmed);
for kk = 1:n + 1
    at_sep = (kk > n) || (trimmed(kk) == '/');
    if at_sep
        if kk > start_idx
            tokens{end + 1, 1} = trimmed(start_idx:kk - 1); %#ok<AGROW>
        elseif kk == 1 && is_abs
            % Leading separator: no token, absolute preserved below.
        else
            % Empty from duplicate separators (already collapsed) or
            % trailing separator: skip.
        end
        start_idx = kk + 1;
    end
end
stack = {};
for kk = 1:numel(tokens)
    tok = tokens{kk};
    if isempty(tok) || strcmp(tok, '.')
        continue;
    end
    if strcmp(tok, '..') || ~isempty(strfind(tok, '..'))
        collapsed = '';
        return;
    end
    stack{end + 1, 1} = tok; %#ok<AGROW>
end
if is_abs
    if isempty(stack)
        collapsed = '/';
    else
        collapsed = '/';
        for kk = 1:numel(stack)
            if kk > 1
                collapsed = [collapsed '/']; %#ok<AGROW>
            end
            collapsed = [collapsed stack{kk}]; %#ok<AGROW>
        end
    end
else
    if isempty(stack)
        collapsed = '';
        return;
    end
    collapsed = '';
    for kk = 1:numel(stack)
        if kk > 1
            collapsed = [collapsed '/']; %#ok<AGROW>
        end
        collapsed = [collapsed stack{kk}]; %#ok<AGROW>
    end
end
end

function local_reject_traversal(path_text, label)
% Controlled paths never contain parent-directory traversal.
if ~isempty(strfind(path_text, '..'))
    error('pseudo_CT:MLSCPayloadManifest', ...
        '%s must not contain parent-directory traversal.', label);
end
end

function local_require_controlled_nii(path_text, label, failure_id)
% Controlled NIfTI basename: single-row string, no traversal, .nii suffix
% (an optional trailing ',1' volume selector is tolerated for SPM-style
% references). Data only: never sourced, eval'd, or passed to a shell.
if ~ischar(path_text) || size(path_text, 1) ~= 1 || isempty(strtrim(path_text))
    error(failure_id, '%s must be a non-empty string.', label);
end
trimmed = strtrim(path_text);
if ~isempty(strfind(trimmed, '..'))
    error(failure_id, '%s must not contain parent-directory traversal.', label);
end
stripped = trimmed;
if length(stripped) >= 2 && strcmp(stripped(end-1:end), ',1')
    stripped = stripped(1:end-2);
end
if length(stripped) < 5 || ~strcmp(lower(stripped(end-3:end)), '.nii')
    error(failure_id, '%s must reference a .nii file.', label);
end
end

function text = local_fingerprint(path_text)
% Version/fingerprint probe: bytes + datenum via dir(), R2010b-safe.
% Missing files report 'missing' here; callers fail closed with error().
info = dir(path_text);
if isempty(info)
    text = 'missing';
    return;
end
text = sprintf('bytes=%d;datenum=%.6f', info(1).bytes, info(1).datenum);
end

function local_write_text_file(path_text, lines, failure_id)
% Fail-closed text evidence writer: checks every write/error/close outcome
% and raises on incomplete evidence with reliable handle cleanup. An
% empty/truncated file can never pass. Every failure raises (nonzero
% propagation); evidence is required for finalization.
fid = -1;
expected_total = 0;
for kk = 1:length(lines)
    if ~ischar(lines{kk}) || size(lines{kk}, 1) ~= 1
        error(failure_id, 'Evidence content is invalid for: %s', path_text);
    end
    expected_total = expected_total + length(lines{kk}) + 1;
end
try
    fid = fopen(path_text, 'w');
    if fid == -1
        error(failure_id, 'Cannot write evidence file: %s', path_text);
    end
    for ii = 1:length(lines)
        expected_here = length(lines{ii}) + 1;
        count = fprintf(fid, '%s\n', lines{ii});
        if ~isnumeric(count) || isempty(count) || count ~= expected_here
            error(failure_id, 'Evidence write incomplete: %s', path_text);
        end
    end
    [~, ferr_num] = ferror(fid);
    if ferr_num ~= 0
        error(failure_id, 'Evidence write error: %s', path_text);
    end
    close_status = fclose(fid);
    fid = -1;
    if close_status ~= 0
        error(failure_id, 'Evidence close failed: %s', path_text);
    end
    if exist(path_text, 'file') ~= 2
        error(failure_id, 'Evidence file not verified: %s', path_text);
    end
    info_here = dir(path_text);
    if isempty(info_here) || info_here(1).bytes == 0
        error(failure_id, 'Evidence file is empty: %s', path_text);
    end
    if info_here(1).bytes < expected_total
        error(failure_id, 'Evidence file is incomplete: %s', path_text);
    end
catch ME
    if fid ~= -1
        try
            fclose(fid);
        catch %#ok<CTCH>
        end
        fid = -1;
    end
    if isstruct(ME) && isfield(ME, 'identifier') && ischar(ME.identifier) && ...
            strcmp(ME.identifier, failure_id)
        rethrow(ME);
    end
    if isstruct(ME) && isfield(ME, 'message') && ischar(ME.message) && ~isempty(strtrim(ME.message))
        error(failure_id, 'Evidence write failed: %s (%s)', path_text, strtrim(ME.message));
    end
    error(failure_id, 'Evidence write failed: %s', path_text);
end
end

function local_write_prepare_evidence(evidence_path, job, handoff, atlas_dir)
% Handoff evidence: effective prepare inputs/settings plus fingerprints of
% the actual current resources (atlas list, ch2, batches, templates, SPM
% toolbox TPM when discoverable, bundled QC colormap). Fixed basename.
lines = {'schema: pseudo-CT.mlsc-current-prepare-evidence/v1', ...
    sprintf('input_selected: %s', strtrim(handoff.input_selected)), ...
    sprintf('needs_normalization: %d', logical(handoff.needs_normalization)), ...
    sprintf('normalized_expected: %s', strtrim(handoff.normalized_expected)), ...
    sprintf('aliasing_effective: %d', logical(handoff.aliasing_effective)), ...
    sprintf('recenter_effective: %d', logical(handoff.recenter_effective)), ...
    sprintf('atlas_dir: %s', strtrim(atlas_dir)), ...
    sprintf('work_dir: %s', strtrim(job.work_dir)), ...
    sprintf('code_version: %s', handoff.code_version), ...
    'handoff_file: mlsc_current_handoff.mat'};
required_here = {'ch2.nii'; 'new_segment_batch.mat'; ...
    'dartel_existing_template_batch.mat'; 'create_inverse_warped_batch.mat'; ...
    'Template_1.nii'; 'Template_2.nii'; 'Template_3.nii'; ...
    'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'};
for ii = 1:length(required_here)
    lines{end + 1} = sprintf('resource %s: %s', required_here{ii}, ...
        local_fingerprint(fullfile(atlas_dir, required_here{ii}))); %#ok<AGROW>
end
found = dir(fullfile(atlas_dir, '*Atlas*.nii'));
for ii = 1:length(found)
    lines{end + 1} = sprintf('resource atlas %s: %s', found(ii).name, ...
        local_fingerprint(fullfile(atlas_dir, found(ii).name))); %#ok<AGROW>
end
if exist('spm', 'file') == 2
    tpm_here = fullfile(spm('Dir'), 'toolbox', 'Seg', 'TPM.nii');
    lines{end + 1} = sprintf('resource SPM-toolbox-TPM.nii: %s', ...
        local_fingerprint(tpm_here)); %#ok<AGROW>
else
    lines{end + 1} = 'resource SPM-toolbox-TPM.nii: undiscoverable-here;headless-gate-authoritative'; %#ok<AGROW>
end
hot_map_here = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'qc', 'hot_map_mpitool_1024.mat');
lines{end + 1} = sprintf('resource hot_map_mpitool_1024.mat: %s', ...
    local_fingerprint(hot_map_here)); %#ok<AGROW>
local_write_text_file(evidence_path, lines, 'pseudo_CT:MLSCPayloadPrepare');
end

function local_write_output_verification(evidence_path, handoff_path, handoff, normalized_input, required_outputs)
% Normalization + output-verification evidence: the verified normalized
% input produced by the external FreeSurfer step (consumed only after the
% existence check in the compute phase) and every required emit-contract
% output with fingerprints plus the narrow structured att_map semantic
% block. Fixed basename. NON-SCIENTIFIC metadata/evidence only: this
% extension reads the emitted att_map.nii header/data for evidence and
% changes no image operation, ordering, threshold, dtype, mask,
% registration, seg, or DARTEL behavior.
lines = {'schema: pseudo-CT.mlsc-current-output-verification/v1', ...
    sprintf('handoff: %s', handoff_path), ...
    sprintf('needs_normalization: %d', logical(handoff.needs_normalization)), ...
    sprintf('normalized_input_verified: %s', strtrim(normalized_input)), ...
    sprintf('normalized_input: %s', local_fingerprint_sha(strtrim(normalized_input)))};
for ii = 1:length(required_outputs)
    [~, base_name, ext_name] = fileparts(required_outputs{ii});
    lines{end + 1} = sprintf('output %s%s: %s', base_name, ext_name, ...
        local_fingerprint_sha(required_outputs{ii})); %#ok<AGROW>
end
% Structured att_map semantic block tied to the exact emitted file.
att_map_path = '';
for ii = 1:length(required_outputs)
    [~, base_name, ext_name] = fileparts(required_outputs{ii});
    if strcmp([base_name ext_name], 'att_map.nii')
        att_map_path = required_outputs{ii};
        break;
    end
end
if isempty(att_map_path)
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence requires att_map.nii.');
end
semantic_lines = local_att_map_semantic_lines(att_map_path);
for ii = 1:length(semantic_lines)
    lines{end + 1} = semantic_lines{ii}; %#ok<AGROW>
end
local_write_text_file(evidence_path, lines, 'pseudo_CT:MLSCPayloadCompute');
end

function fingerprint = local_fingerprint_sha(path_text)
% Fingerprint with mandatory content hash (B5A): bytes/datenum plus
% SHA-256. If SHA-256 is unavailable the caller fails closed (no
% size-only fallback). R2010b-safe.
base = local_fingerprint(path_text);
sha = local_file_sha256_hex(path_text);
if isempty(sha)
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Output identity hashing is unavailable: %s', path_text);
end
fingerprint = sprintf('%s;sha256=%s', base, lower(strtrim(sha)));
end

function hex = local_file_sha256_hex(path_name)
%LOCAL_FILE_SHA256_HEX SHA-256, fail-closed (B4B/B5A). Java when
%   available, else approved sha256sum. No FNV fallback. R2010b only.
hex = '';
try
    fid = fopen(path_name, 'r');
    if fid == -1
        return;
    end
    raw = fread(fid, inf, '*uint8')';
    fclose(fid);
    if isempty(raw)
        return;
    end
    try
        digest = java.security.MessageDigest.getInstance('SHA-256');
        digest.update(raw);
        bytes = typecast(digest.digest(), 'uint8');
        candidate = lower(reshape(dec2hex(bytes, 2)', 1, []));
        if ischar(candidate) && length(candidate) == 64 && ...
                ~isempty(regexp(candidate, '^[0-9a-f]{64}$', 'once'))
            hex = candidate;
            return;
        end
    catch %#ok<CTCH>
    end
    try
        quoted = local_shell_quote_path(path_name);
        [status, out] = system(['sha256sum ' quoted ' 2>/dev/null']);
        if status == 0 && ischar(out) && ~isempty(strtrim(out))
            tok = regexp(strtrim(out), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', ...
                'tokens', 'once');
            if ~isempty(tok)
                candidate = lower(strtrim(tok{1}));
                if length(candidate) == 64 && ...
                        ~isempty(regexp(candidate, '^[0-9a-f]{64}$', 'once'))
                    hex = candidate;
                    return;
                end
            end
        end
    catch %#ok<CTCH>
    end
    hex = '';
catch %#ok<CTCH>
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    hex = '';
end
end

function quoted = local_shell_quote_path(value)
quoted = '''''';
try
    if ~ischar(value) || size(value, 1) ~= 1 || isempty(value)
        quoted = '''''';
        return;
    end
    single_quote = char(39);
    double_quote = char(34);
    quoted = single_quote;
    for ii = 1:length(value)
        if value(ii) == char(0)
            error('pseudo_CT:MLSCPayloadCompute', 'NUL in path.');
        elseif value(ii) == single_quote
            quoted = [quoted single_quote double_quote single_quote ...
                double_quote single_quote]; %#ok<AGROW>
        else
            quoted = [quoted value(ii)]; %#ok<AGROW>
        end
    end
    quoted = [quoted single_quote];
catch %#ok<CTCH>
    quoted = '''''';
end
end

function lines = local_att_map_semantic_lines(att_map_path)
% Structured att_map evidence (metadata only, no science change).
% Emits exact basename/path identity, SHA-256, byte size, NIfTI datatype,
% dimensions, finite-value flag, and affine/geometry identity. Fails closed
% on missing/malformed/wrong dims/dtype/affine/nonfinite. R2010b only.
lines = {};
if ~ischar(att_map_path) || size(att_map_path, 1) ~= 1 || ...
        isempty(strtrim(att_map_path))
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence path is invalid.');
end
if exist(strtrim(att_map_path), 'file') ~= 2
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence file is missing.');
end
info = dir(strtrim(att_map_path));
if isempty(info) || info(1).bytes <= 0
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence file is empty.');
end
sha = local_file_sha256_hex(strtrim(att_map_path));
if isempty(sha)
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence hash is unavailable.');
end
if exist('spm_vol', 'file') ~= 2
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence requires SPM header access.');
end
try
    V = spm_vol(strtrim(att_map_path));
catch %#ok<CTCH>
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence header is unreadable.');
end
if ~isstruct(V) || isempty(V)
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence header is invalid.');
end
V = V(1);
if ~isfield(V, 'dim') || ~isfield(V, 'mat') || ~isfield(V, 'dt')
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence header is malformed.');
end
if ~isnumeric(V.dim) || numel(V.dim) < 3 || any(~isfinite(V.dim(:))) || ...
        any(V.dim(:) <= 0)
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence dimensions are invalid.');
end
if ~isnumeric(V.mat) || numel(V.mat) ~= 16 || any(~isfinite(V.mat(:))) || ...
        isequal(V.mat, zeros(size(V.mat)))
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence affine is invalid.');
end
if ~isnumeric(V.dt) || isempty(V.dt) || V.dt(1) ~= 16
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence datatype is invalid.');
end
try
    data = spm_read_vols(V);
catch %#ok<CTCH>
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence data is unreadable.');
end
if ~isnumeric(data) && ~islogical(data)
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence data is invalid.');
end
if isempty(data) || ~all(isfinite(data(:)))
    error('pseudo_CT:MLSCPayloadCompute', ...
        'Structured att_map evidence data is nonfinite.');
end
dim_text = sprintf('%g ', V.dim(:)');
dim_text = strtrim(dim_text);
% B5C lossless affine: %.17g guarantees exact IEEE-754 double round-trip
% (no tolerance on compare). %.10f truncated (~3e-11) and is forbidden.
affine_text = sprintf('%.17g ', V.mat(:)');
affine_text = strtrim(affine_text);
lines = {'att_map_basename: att_map.nii', ...
    sprintf('att_map_bytes: %d', double(info(1).bytes)), ...
    sprintf('att_map_sha256: %s', lower(strtrim(sha))), ...
    sprintf('att_map_datatype: %d', double(V.dt(1))), ...
    sprintf('att_map_dim: %s', dim_text), ...
    sprintf('att_map_affine: %s', affine_text), ...
    'att_map_finite: 1'};
end
