function test_mlsc_current_payload_boundary()
%TEST_MLSC_CURRENT_PAYLOAD_BOUNDARY T003 payload-boundary gate (offline).
%   Covers the T003 blocker only: complete dependency inventory with
%   A/B/C/D classes, intended-root resolvability, and fail-closed native
%   evidence. No live SSH/Slurm/subject/Runtime/submission and no real
%   science beyond the cheap prepare header read + handoff.
%
%   1) Omitted genuinely-required dependency (nlinfit, via move_image_2_MNI
%      hist fit, also covering imfill/bwlabel/spm_run_coreg_estimate in the
%      same bounded audit): otherwise-valid fixtures with nlinfit removed
%      from the path must fail with MLSCPayloadDependency identifying
%      nlinfit, BEFORE either shared helper executes, with no side effects
%      (no handoff/evidence files).
%   2) Omitted segmentation native (reachable spm_slice_vol/spm_conv_vol via
%      vers spm_preproc_write8 decimate/reslice generating rc* consumed by
%      compute): otherwise-valid fixtures with a manifest covering only the
%      old three-file native set must fail with NativeEvidence, BEFORE
%      either helper, with no side effects.
%   3) Shadow identity: a higher-priority alternate native earlier on the
%      path (resolved != authoritative SPM-Dir file) must fail with
%      NativeMismatch, BEFORE either helper, with no side effects.
%   4) Native evidence negative (genuinely-required spm_sample_vol MEX file
%      present on disk): otherwise-valid fixtures with absent/invalid native
%      evidence must fail (NativeEvidence/NativeMismatch), BEFORE either
%      helper, with no side effects. Existence never claims loadability;
%      production validated-load evidence belongs to T007/Gate A.
%   5) Positive boundary: complete manifest passes validation and reaches
%      the shared prepare helper offline (cheap header read + handoff, no
%      SPM batch/segmentation/DARTEL), writing the bounded handoff and
%      prepare evidence.
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
addpath(fullfile(root_dir, 'vers'), '-begin');

spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
aliasing_root = '/usr/pubsw/packages/mrpet/standalone_apps/correct_aliasing/correct_aliasing_standalone-latest';
atlas_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/Batch_atlas';
assert(exist(spm_root, 'dir') == 7, 'SPM fixture root unavailable for offline boundary test.');
assert(exist(aliasing_root, 'dir') == 7, 'Aliasing fixture root unavailable for offline boundary test.');
assert(exist(atlas_root, 'dir') == 7, 'Atlas fixture root unavailable for offline boundary test.');
addpath(genpath(spm_root), '-begin');
addpath(fullfile(spm_root, 'matlabbatch'), '-begin');
addpath(aliasing_root, '-begin');

% Omitted-dependency fixture: nlinfit must be discoverable here so that
% removing it later proves the gate (not the fixture) rejects.
assert(exist('nlinfit', 'file') == 2, 'nlinfit fixture precondition failed.');
assert(exist('spm_run_coreg_estimate', 'file') == 2, 'spm_run_coreg_estimate fixture precondition failed.');

test_root = tempname;
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

% Positive fixtures: real ch2 input (no copy), temp work dir, real atlas
% tree, manifest fingerprints computed from disk (deterministic offline).
work_dir = fullfile(test_root, 'work');
mkdir(work_dir);
input_nii = fullfile(atlas_root, 'ch2.nii');
job_path = fullfile(test_root, 'job.mat');
resource_path = fullfile(test_root, 'resources.mat');
local_write_valid_fixtures(job_path, resource_path, input_nii, work_dir, atlas_root, spm_root, root_dir);

% Positive: complete manifest passes validation and reaches prepare helper
% (cheap path: aliasing/recenter off, single input, real header read).
mlsc_current_payload('prepare', job_path, resource_path);
handoff_path = fullfile(work_dir, 'mlsc_current_handoff.mat');
evidence_path = fullfile(work_dir, 'mlsc_current_prepare_evidence.txt');
assert(exist(handoff_path, 'file') == 2, 'Positive boundary did not reach the prepare handoff.');
assert(exist(evidence_path, 'file') == 2, 'Positive boundary did not write prepare evidence.');
loaded = load(handoff_path);
assert(isfield(loaded, 'handoff') && isstruct(loaded.handoff) && numel(loaded.handoff) == 1, 'Handoff content invalid.');
assert(strcmp(loaded.handoff.schema, 'pseudo-CT.current-handoff/v1'), 'Handoff schema mismatch.');
assert(~loaded.handoff.aliasing_effective && ~loaded.handoff.recenter_effective, 'Positive fixture flags mismatch.');
% No compute science ran on the prepare phase (no attenuation outputs).
assert(exist(fullfile(work_dir, 'att_map.nii'), 'file') ~= 2, 'Prepare phase must not run compute science.');

% Omitted genuinely-required dependency: remove the Statistics Toolbox dir
% providing nlinfit (single provider on this host), then the same
% otherwise-valid fixtures must fail identifying nlinfit BEFORE either
% helper executes, with no side effects.
work_omitted = fullfile(test_root, 'work-omitted');
mkdir(work_omitted);
job_omitted = fullfile(test_root, 'job-omitted.mat');
resource_omitted = fullfile(test_root, 'resources-omitted.mat');
local_write_valid_fixtures(job_omitted, resource_omitted, input_nii, work_omitted, atlas_root, spm_root, root_dir);
stats_dir = fileparts(which('nlinfit'));
assert(~isempty(stats_dir), 'nlinfit provider dir undiscoverable.');
old_path = path();
restore_path = onCleanup(@() path(old_path)); %#ok<NASGU>
rmpath(stats_dir);
clear('nlinfit');
assert(exist('nlinfit', 'file') == 0, 'nlinfit removal precondition failed.');
failed = false;
actual_id = '';
actual_msg = '';
try
    mlsc_current_payload('prepare', job_omitted, resource_omitted);
catch ME
    failed = true;
    actual_id = ME.identifier;
    actual_msg = ME.message;
end
assert(failed, 'Omitted-dependency gate did not fail closed.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadDependency'), 'Unexpected omitted-dependency identifier: %s', actual_id);
assert(~isempty(strfind(actual_msg, 'nlinfit')), 'Omitted-dependency gate did not identify nlinfit.');
assert(exist(fullfile(work_omitted, 'mlsc_current_handoff.mat'), 'file') ~= 2, 'Omitted gate ran with side effects.');
assert(exist(fullfile(work_omitted, 'mlsc_current_prepare_evidence.txt'), 'file') ~= 2, 'Omitted gate ran with side effects.');
path(old_path);
clear restore_path;
assert(exist('nlinfit', 'file') == 2, 'nlinfit path restoration failed.');

% Native evidence negative: real MEX files stay present, but manifest
% evidence is absent/invalid -> fail closed BEFORE either helper, no side
% effects. Uses genuinely-required spm_sample_vol (vers preproc path).
work_native = fullfile(test_root, 'work-native');
mkdir(work_native);
job_native = fullfile(test_root, 'job-native.mat');
resource_native = fullfile(test_root, 'resources-native.mat');
local_write_valid_fixtures(job_native, resource_native, input_nii, work_native, atlas_root, spm_root, root_dir);
assert(exist(fullfile(spm_root, 'spm_sample_vol.mexa64'), 'file') ~= 0, 'Native file precondition failed.');
tampered = load(resource_native);
tampered.resources.native_validation = '';
resources = tampered.resources;
save(resource_native, 'resources');
failed = false;
actual_id = '';
try
    mlsc_current_payload('prepare', job_native, resource_native);
catch ME
    failed = true;
    actual_id = ME.identifier;
end
assert(failed, 'Native-evidence gate did not fail closed on invalid validation.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadNativeEvidence'), 'Unexpected native-evidence identifier: %s', actual_id);
assert(exist(fullfile(work_native, 'mlsc_current_handoff.mat'), 'file') ~= 2, 'Native gate ran with side effects.');
tampered = load(resource_native);
tampered.resources.native_validation = 't007-gate-a-pending: existence-only; production loadability evidence comes later';
idx = local_find_native(tampered.resources.native_names, 'spm_sample_vol.mexa64');
assert(idx > 0, 'Native fixture precondition failed.');
tampered.resources.native_fingerprints{idx} = 'bytes=0;datenum=0.000000';
resources = tampered.resources;
save(resource_native, 'resources');
failed = false;
actual_id = '';
try
    mlsc_current_payload('prepare', job_native, resource_native);
catch ME
    failed = true;
    actual_id = ME.identifier;
end
assert(failed, 'Native-mismatch gate did not fail closed on wrong fingerprint.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadNativeMismatch'), 'Unexpected native-mismatch identifier: %s', actual_id);
assert(exist(fullfile(work_native, 'mlsc_current_handoff.mat'), 'file') ~= 2, 'Native gate ran with side effects.');

% Omitted segmentation native: reachable spm_slice_vol (vers
% spm_preproc_write8 decimate/reslice generating rc* consumed by compute)
% omitted from an otherwise-valid manifest must fail with NativeEvidence
% BEFORE either helper, with no side effects.
work_seg = fullfile(test_root, 'work-seg');
mkdir(work_seg);
job_seg = fullfile(test_root, 'job-seg.mat');
resource_seg = fullfile(test_root, 'resources-seg.mat');
local_write_valid_fixtures(job_seg, resource_seg, input_nii, work_seg, atlas_root, spm_root, root_dir);
assert(exist(fullfile(spm_root, 'spm_slice_vol.mexa64'), 'file') ~= 0, 'Segmentation native precondition failed.');
assert(exist(fullfile(spm_root, 'spm_conv_vol.mexa64'), 'file') ~= 0, 'Segmentation native precondition failed.');
tampered = load(resource_seg);
drop = local_find_native(tampered.resources.native_names, 'spm_slice_vol.mexa64');
assert(drop > 0, 'Segmentation fixture precondition failed.');
tampered.resources.native_names(drop) = [];
tampered.resources.native_fingerprints(drop) = [];
tampered.resources.native_types(drop) = [];
resources = tampered.resources;
save(resource_seg, 'resources');
failed = false;
actual_id = '';
actual_msg = '';
try
    mlsc_current_payload('prepare', job_seg, resource_seg);
catch ME
    failed = true;
    actual_id = ME.identifier;
    actual_msg = ME.message;
end
assert(failed, 'Omitted-segmentation-native gate did not fail closed.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadNativeEvidence'), 'Unexpected omitted-segmentation identifier: %s', actual_id);
assert(exist(fullfile(work_seg, 'mlsc_current_handoff.mat'), 'file') ~= 2, 'Segmentation gate ran with side effects.');
assert(exist(fullfile(work_seg, 'mlsc_current_prepare_evidence.txt'), 'file') ~= 2, 'Segmentation gate ran with side effects.');

% Shadow identity: a higher-priority alternate native earlier on the path
% (resolved != authoritative SPM-Dir file) must fail with NativeMismatch
% BEFORE either helper, with no side effects.
work_shadow = fullfile(test_root, 'work-shadow');
mkdir(work_shadow);
job_shadow = fullfile(test_root, 'job-shadow.mat');
resource_shadow = fullfile(test_root, 'resources-shadow.mat');
local_write_valid_fixtures(job_shadow, resource_shadow, input_nii, work_shadow, atlas_root, spm_root, root_dir);
shadow_dir = fullfile(test_root, 'shadow');
mkdir(shadow_dir);
copyfile(fullfile(spm_root, 'spm_sample_vol.mexa64'), fullfile(shadow_dir, 'spm_sample_vol.mexa64'));
assert(exist(fullfile(shadow_dir, 'spm_sample_vol.mexa64'), 'file') ~= 0, 'Shadow fixture precondition failed.');
old_shadow_path = path();
addpath(shadow_dir, '-begin');
rehash path;
assert(~isempty(strfind(which('spm_sample_vol'), shadow_dir)), 'Shadow fixture did not take path priority.');
failed = false;
actual_id = '';
actual_msg = '';
try
    mlsc_current_payload('prepare', job_shadow, resource_shadow);
catch ME
    failed = true;
    actual_id = ME.identifier;
    actual_msg = ME.message;
end
path(old_shadow_path);
rehash path;
assert(failed, 'Shadow-identity gate did not fail closed.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadNativeMismatch'), 'Unexpected shadow-identity identifier: %s', actual_id);
assert(~isempty(strfind(actual_msg, 'spm_sample_vol')), 'Shadow-identity gate did not identify spm_sample_vol.');
assert(exist(fullfile(work_shadow, 'mlsc_current_handoff.mat'), 'file') ~= 2, 'Shadow gate ran with side effects.');
assert(exist(fullfile(work_shadow, 'mlsc_current_prepare_evidence.txt'), 'file') ~= 2, 'Shadow gate ran with side effects.');

% R2010b-era parse compatibility for the touched payload seam.
try
    mlint(fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_payload.m'));
catch ME %#ok<NASGU>
    assert(false, 'Payload seam failed to parse.');
end

fprintf('=== MLSC current payload boundary tests passed: omitted nlinfit, omitted segmentation native, shadow identity, native evidence, positive prepare ===\n');
end

function local_write_valid_fixtures(job_path, resource_path, input_nii, work_dir, atlas_root, spm_root, root_dir)
job = struct();
job.schema = 'pseudo-CT.mlsc-current-job/v1';
job.manifest_version = 1;
job.input_mprage = input_nii;
job.work_dir = work_dir;
job.atlas_dir = atlas_root;
job.check_aliasing = 0;
job.recenter_before_normalization = 'No';
job.bone_enabled = false;
job.zero_background = 'No';
save(job_path, 'job');
fixed = {'ch2.nii'; 'new_segment_batch.mat'; ...
    'dartel_existing_template_batch.mat'; 'create_inverse_warped_batch.mat'; ...
    'Template_1.nii'; 'Template_2.nii'; 'Template_3.nii'; ...
    'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'};
found = dir(fullfile(atlas_root, '*Atlas*.nii'));
atlas_list = {};
for ii = 1:length(found)
    atlas_list{end + 1, 1} = found(ii).name; %#ok<AGROW>
end
resource_names = fixed;
for ii = 1:length(atlas_list)
    resource_names{end + 1, 1} = atlas_list{ii}; %#ok<AGROW>
end
resource_fingerprints = {};
for ii = 1:length(resource_names)
    resource_fingerprints{end + 1, 1} = local_fingerprint(fullfile(atlas_root, resource_names{ii})); %#ok<AGROW>
end
tpm_path = fullfile(spm_root, 'toolbox', 'Seg', 'TPM.nii');
qc_path = fullfile(root_dir, 'src', 'qc', 'hot_map_mpitool_1024.mat');
resources = struct();
resources.schema = 'pseudo-CT.mlsc-current-resources/v1';
resources.manifest_version = 1;
resources.atlas_dir = atlas_root;
resources.atlas_list = atlas_list;
resources.resource_names = resource_names;
resources.resource_fingerprints = resource_fingerprints;
resources.tpm_fingerprint = local_fingerprint(tpm_path);
resources.qc_fingerprint = local_fingerprint(qc_path);
resources.native_names = {'spm_sample_vol.mexa64'; 'spm_bsplinc.mexa64'; 'spm_bsplins.mexa64'; 'spm_slice_vol.mexa64'; 'spm_conv_vol.mexa64'};
resources.native_fingerprints = {local_fingerprint(fullfile(spm_root, 'spm_sample_vol.mexa64')); ...
    local_fingerprint(fullfile(spm_root, 'spm_bsplinc.mexa64')); ...
    local_fingerprint(fullfile(spm_root, 'spm_bsplins.mexa64')); ...
    local_fingerprint(fullfile(spm_root, 'spm_slice_vol.mexa64')); ...
    local_fingerprint(fullfile(spm_root, 'spm_conv_vol.mexa64'))};
resources.native_types = {'MEX'; 'MEX'; 'MEX'; 'MEX'; 'MEX'};
resources.native_platform = 'glnxa64';
resources.native_arch = 'glnxa64';
resources.native_validation = 't007-gate-a-pending: existence-only; production loadability evidence comes later';
save(resource_path, 'resources');
end

function text = local_fingerprint(path_text)
info = dir(path_text);
assert(~isempty(info), 'Fixture fingerprint missing: %s', path_text);
text = sprintf('bytes=%d;datenum=%.6f', info(1).bytes, info(1).datenum);
end

function idx = local_find_native(names_in, target)
idx = 0;
for kk = 1:numel(names_in)
    if strcmp(strtrim(names_in{kk}), target)
        idx = kk;
        return;
    end
end
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
