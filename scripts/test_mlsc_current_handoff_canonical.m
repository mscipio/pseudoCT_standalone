function test_mlsc_current_handoff_canonical()
%TEST_MLSC_CURRENT_HANDOFF_CANONICAL T009 narrow remediation regression (A-G).
%   Offline only (no live SSH/Slurm/subject/Runtime/submission, no science
%   beyond the COMPUTE validation boundary). Proves the representation/
%   canonicalization defect and its payload-only repair:
%     mprage.nii (manifest basename, relative) + PREPARE absolute
%     .../mprage_corrected.nii + normalized absolute
%     .../mprage_corrected_normalized.nii entering COMPUTE validation.
%   Before fix: bare strcmp rejects equivalent references with
%     pseudo_CT:MLSCPayloadCompute 'Handoff input does not match'.
%   After fix: canonical identity within the bound work dir accepts the
%   legitimate forms and still rejects same-basename/different-dir, wrong
%   basename, traversal, and inconsistent normalized. No same-basename
%   acceptance, no basename equality, no different-dir, no .. traversal, no
%   fallback, no removal of controlled-NIfTI checks.
%
%   Cases (all via mlsc_current_payload COMPUTE validation, stub science
%   only after the validation boundary by omitting the normalized file so
%   PASS cases reach the next legitimate boundary
%   'Verified normalized input missing' instead of science):
%     A relative original PASS (relative selected vs relative manifest)
%     B absolute corrected PASS (defect: absolute _corrected vs basename)
%     C ./corrected PASS (dot-prefixed corrected vs basename)
%     D same-basename other-dir FAIL
%     E wrong corrected basename FAIL
%     F traversal FAIL
%     G inconsistent normalized FAIL
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
addpath(fullfile(root_dir, 'vers'), '-begin');

spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
aliasing_root = '/usr/pubsw/packages/mrpet/standalone_apps/correct_aliasing/correct_aliasing_standalone-latest';
atlas_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/Batch_atlas';
assert(exist(spm_root, 'dir') == 7, 'SPM fixture root unavailable.');
assert(exist(aliasing_root, 'dir') == 7, 'Aliasing fixture root unavailable.');
assert(exist(atlas_root, 'dir') == 7, 'Atlas fixture root unavailable.');
addpath(genpath(spm_root), '-begin');
addpath(fullfile(spm_root, 'matlabbatch'), '-begin');
addpath(aliasing_root, '-begin');
assert(exist('spm_vol', 'file') == 2, 'spm_vol unavailable.');
assert(exist('correct_aliasing', 'file') == 2, 'correct_aliasing unavailable.');

test_root = tempname;
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>
work = fullfile(test_root, 'work');
mkdir(work);
other = fullfile(test_root, 'other');
mkdir(other);
% Dummy NIfTI inputs (existence only; validation boundary never reads headers).
local_write(fullfile(work, 'mprage.nii'), 'dummy-mprage');
local_write(fullfile(work, 'mprage_corrected.nii'), 'dummy-corrected');
local_write(fullfile(other, 'mprage.nii'), 'dummy-other');
% Note: normalized files are intentionally absent so PASS cases stop at the
% next legitimate boundary (Verified normalized input missing), never science.

resource_path = fullfile(test_root, 'resources.mat');
local_write_valid_resources(resource_path, atlas_root, spm_root, root_dir);

% A relative original PASS: manifest basename + handoff relative original.
job_a = fullfile(test_root, 'job-a.mat');
local_write_job(job_a, 'mprage.nii', work, atlas_root);
handoff_a_selected = 'mprage.nii';
handoff_a_expected = 'mprage_normalized.nii';
local_write_handoff(work, handoff_a_selected, handoff_a_expected, true, atlas_root);
local_assert_next_boundary(job_a, resource_path, work, ...
    'A relative original PASS');

% B absolute corrected PASS (defect reproduction): manifest basename +
% PREPARE absolute .../mprage_corrected.nii + normalized absolute.
job_b = fullfile(test_root, 'job-b.mat');
local_write_job(job_b, 'mprage.nii', work, atlas_root);
handoff_b_selected = fullfile(work, 'mprage_corrected.nii');
handoff_b_expected = fullfile(work, 'mprage_corrected_normalized.nii');
local_write_handoff(work, handoff_b_selected, handoff_b_expected, true, atlas_root);
local_assert_next_boundary(job_b, resource_path, work, ...
    'B absolute corrected PASS (defect)');

% C ./corrected PASS.
job_c = fullfile(test_root, 'job-c.mat');
local_write_job(job_c, 'mprage.nii', work, atlas_root);
handoff_c_selected = './mprage_corrected.nii';
handoff_c_expected = './mprage_corrected_normalized.nii';
local_write_handoff(work, handoff_c_selected, handoff_c_expected, true, atlas_root);
local_assert_next_boundary(job_c, resource_path, work, ...
    'C ./corrected PASS');

% D same-basename other-dir FAIL (must not accept basename equality).
job_d = fullfile(test_root, 'job-d.mat');
local_write_job(job_d, fullfile(work, 'mprage.nii'), work, atlas_root);
handoff_d_selected = fullfile(other, 'mprage.nii');
handoff_d_expected = fullfile(other, 'mprage_normalized.nii');
local_write_handoff(work, handoff_d_selected, handoff_d_expected, true, atlas_root);
local_assert_input_mismatch(job_d, resource_path, work, ...
    'D same-basename other-dir FAIL');

% E wrong corrected basename FAIL.
job_e = fullfile(test_root, 'job-e.mat');
local_write_job(job_e, fullfile(work, 'mprage.nii'), work, atlas_root);
handoff_e_selected = fullfile(work, 'mprage_wrong.nii');
handoff_e_expected = fullfile(work, 'mprage_wrong_normalized.nii');
local_write_handoff(work, handoff_e_selected, handoff_e_expected, true, atlas_root);
local_assert_input_mismatch(job_e, resource_path, work, ...
    'E wrong corrected basename FAIL');

% F traversal FAIL (controlled NIfTI rejects .. before/ besides identity).
job_f = fullfile(test_root, 'job-f.mat');
local_write_job(job_f, fullfile(work, 'mprage.nii'), work, atlas_root);
handoff_f_selected = '../evil.nii';
handoff_f_expected = '../evil_normalized.nii';
local_write_handoff(work, handoff_f_selected, handoff_f_expected, true, atlas_root);
local_assert_traversal_or_mismatch(job_f, resource_path, work, ...
    'F traversal FAIL');

% G inconsistent normalized FAIL (exact derivation required).
job_g = fullfile(test_root, 'job-g.mat');
local_write_job(job_g, fullfile(work, 'mprage.nii'), work, atlas_root);
handoff_g_selected = fullfile(work, 'mprage_corrected.nii');
handoff_g_expected = fullfile(work, 'mprage_WRONG_normalized.nii');
local_write_handoff(work, handoff_g_selected, handoff_g_expected, true, atlas_root);
local_assert_contradictory(job_g, resource_path, work, ...
    'G inconsistent normalized FAIL');

% R2010b parse compatibility for the repaired seam.
try
    mlint(fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_payload.m'));
catch ME %#ok<NASGU>
    assert(false, 'Repaired payload seam failed to parse.');
end

fprintf('=== MLSC current handoff canonical tests passed: A-C PASS to next boundary, D-G FAIL closed (no bypass, no same-basename, no traversal) ===\n');
end

function local_write_job(job_path, input_mprage, work_dir, atlas_dir)
job = struct();
job.schema = 'pseudo-CT.mlsc-current-job/v1';
job.manifest_version = 1;
job.input_mprage = input_mprage;
job.work_dir = work_dir;
job.atlas_dir = atlas_dir;
job.check_aliasing = 0;
job.recenter_before_normalization = 'No';
job.bone_enabled = false;
job.zero_background = 'No';
save(job_path, 'job');
end

function local_write_valid_resources(resource_path, atlas_root, spm_root, root_dir)
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

function local_write_handoff(work_dir, selected, expected, needs_norm, atlas_dir)
handoff = struct();
handoff.schema = 'pseudo-CT.current-handoff/v1';
handoff.input_selected = selected;
handoff.atlas_dir = atlas_dir;
handoff.aliasing_effective = false;
handoff.recenter_effective = false;
handoff.needs_normalization = logical(needs_norm);
handoff.normalized_expected = expected;
handoff.code_version = 'test';
handoff.headless = true;
save(fullfile(work_dir, 'mlsc_current_handoff.mat'), 'handoff');
end

function local_assert_next_boundary(job_path, resource_path, work_dir, label)
% PASS cases must clear the handoff-input gate and stop at the next
% legitimate boundary (Verified normalized input missing), never at
% 'Handoff input does not match'. No science runs (normalized absent).
prev = pwd;
cd(work_dir);
restore = onCleanup(@() cd(prev)); %#ok<NASGU>
failed = false;
actual_id = '';
actual_msg = '';
try
    mlsc_current_payload('compute', job_path, resource_path);
catch ME
    failed = true;
    actual_id = ME.identifier;
    actual_msg = ME.message;
end
clear restore;
assert(failed, '%s: expected fail-closed at next boundary, but passed.', label);
assert(~isempty(strfind(actual_msg, 'Handoff input does not match')) == 0, ...
    '%s: still fails at input gate after fix: %s', label, actual_msg);
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadCompute'), ...
    '%s: unexpected identifier %s', label, actual_id);
assert(~isempty(strfind(actual_msg, 'Verified normalized input missing')), ...
    '%s: did not reach next legitimate boundary: %s', label, actual_msg);
fprintf('%s: PASS to next boundary (Verified missing).\n', label);
end

function local_assert_input_mismatch(job_path, resource_path, work_dir, label)
prev = pwd;
cd(work_dir);
restore = onCleanup(@() cd(prev)); %#ok<NASGU>
failed = false;
actual_id = '';
actual_msg = '';
try
    mlsc_current_payload('compute', job_path, resource_path);
catch ME
    failed = true;
    actual_id = ME.identifier;
    actual_msg = ME.message;
end
clear restore;
assert(failed, '%s: expected input-mismatch FAIL, but passed.', label);
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadCompute'), ...
    '%s: unexpected identifier %s', label, actual_id);
assert(~isempty(strfind(actual_msg, 'Handoff input does not match')), ...
    '%s: wrong failure (expected input mismatch): %s', label, actual_msg);
fprintf('%s: FAIL closed as required.\n', label);
end

function local_assert_traversal_or_mismatch(job_path, resource_path, work_dir, label)
prev = pwd;
cd(work_dir);
restore = onCleanup(@() cd(prev)); %#ok<NASGU>
failed = false;
actual_id = '';
actual_msg = '';
try
    mlsc_current_payload('compute', job_path, resource_path);
catch ME
    failed = true;
    actual_id = ME.identifier;
    actual_msg = ME.message;
end
clear restore;
assert(failed, '%s: expected traversal FAIL, but passed.', label);
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadCompute'), ...
    '%s: unexpected identifier %s', label, actual_id);
is_traversal = ~isempty(strfind(actual_msg, 'traversal'));
is_mismatch = ~isempty(strfind(actual_msg, 'Handoff input does not match'));
assert(is_traversal || is_mismatch, ...
    '%s: wrong failure (expected traversal/mismatch): %s', label, actual_msg);
fprintf('%s: FAIL closed as required.\n', label);
end

function local_assert_contradictory(job_path, resource_path, work_dir, label)
prev = pwd;
cd(work_dir);
restore = onCleanup(@() cd(prev)); %#ok<NASGU>
failed = false;
actual_id = '';
actual_msg = '';
try
    mlsc_current_payload('compute', job_path, resource_path);
catch ME
    failed = true;
    actual_id = ME.identifier;
    actual_msg = ME.message;
end
clear restore;
assert(failed, '%s: expected contradictory FAIL, but passed.', label);
assert(strcmp(actual_id, 'pseudo_CT:MLSCPayloadCompute'), ...
    '%s: unexpected identifier %s', label, actual_id);
assert(~isempty(strfind(actual_msg, 'contradictory')), ...
    '%s: wrong failure (expected contradictory): %s', label, actual_msg);
fprintf('%s: FAIL closed as required.\n', label);
end

function text = local_fingerprint(path_text)
info = dir(path_text);
assert(~isempty(info), 'Fixture fingerprint missing: %s', path_text);
text = sprintf('bytes=%d;datenum=%.6f', info(1).bytes, info(1).datenum);
end

function local_write(path_name, text)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Fixture could not be created.');
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
