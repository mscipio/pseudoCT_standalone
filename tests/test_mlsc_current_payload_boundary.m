function test_mlsc_current_payload_boundary()
%TEST_MLSC_CURRENT_PAYLOAD_BOUNDARY Bounded payload prepare check (offline).
%   Positive boundary: a complete manifest passes validation and reaches
%      the shared prepare helper offline (cheap header read + handoff, no
%      SPM batch/segmentation/DARTEL), writing the bounded handoff and
%      prepare evidence.
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'backends', 'mlsc'), '-begin');
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
addpath(fullfile(root_dir, 'src', 'science', 'overrides'), '-begin');

spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
aliasing_root = fullfile(root_dir, 'external', 'correct_aliasing-0.4.0');
atlas_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/Batch_atlas';
assert(exist(spm_root, 'dir') == 7, 'SPM fixture root unavailable for offline boundary test.');
assert(exist(aliasing_root, 'dir') == 7, 'Aliasing fixture root unavailable for offline boundary test.');
assert(exist(atlas_root, 'dir') == 7, 'Atlas fixture root unavailable for offline boundary test.');
addpath(genpath(spm_root), '-begin');
addpath(fullfile(spm_root, 'matlabbatch'), '-begin');
addpath(aliasing_root, '-begin');

test_root = tempname;
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

% Positive fixtures: real ch2 input (no copy), temp work dir, and real atlas tree.
work_dir = fullfile(test_root, 'work');
mkdir(work_dir);
input_nii = fullfile(atlas_root, 'ch2.nii');
job_path = fullfile(test_root, 'job.mat');
resource_path = fullfile(test_root, 'resources.mat');
local_write_valid_fixtures(job_path, resource_path, input_nii, work_dir, atlas_root);

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

% R2010b-era parse compatibility for the touched payload seam.
try
    mlint(fullfile(root_dir, 'src', 'science', 'current', 'mlsc_current_payload.m'));
catch ME %#ok<NASGU>
    assert(false, 'Payload seam failed to parse.');
end

fprintf('=== MLSC current payload check passed: positive prepare ===\n');
end

function local_write_valid_fixtures(job_path, resource_path, input_nii, work_dir, atlas_root)
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
resources = struct();
resources.schema = 'pseudo-CT.mlsc-current-resources/v1';
resources.manifest_version = 1;
resources.atlas_dir = atlas_root;
resources.atlas_list = atlas_list;
resources.resource_names = resource_names;
save(resource_path, 'resources');
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
