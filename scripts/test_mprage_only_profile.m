function test_mprage_only_profile()
%TEST_MPRAGE_ONLY_PROFILE Focused collection, policy, and promotion seams.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'config'));
addpath(fullfile(root_dir, 'src', 'core'));
addpath(fullfile(root_dir, 'src', 'io'));
addpath(fullfile(root_dir, 'src', 'ui'));

test_dir = tempname;
mkdir(test_dir);
cleanup = onCleanup(@() local_cleanup(test_dir)); %#ok<NASGU>
subject_dir = fullfile(test_dir, 'subject', 'MR');
mkdir(subject_dir);
nifti_input = fullfile(subject_dir, 'mprage.nii');
dicom_input = fullfile(subject_dir, 'mprage.dcm');
local_write(nifti_input, 'NIFTI test input');
local_write(dicom_input, 'DICOM test input');

policy.reference = 'none';
policy.output = 'nifti-only';
policy.gui = 'mprage-only';
[nifti_jobs, nifti_stats] = build_jobs_from_subject_list(nifti_input, 1, policy);
assert(nifti_stats.requested == 1 && nifti_stats.skipped == 0);
assert(length(nifti_jobs) == 1);
assert(strcmp(nifti_jobs(1).mprage_fn, nifti_input));
assert(isempty(nifti_jobs(1).umap_fn));
assert(strcmp(nifti_jobs(1).io_policy.reference, 'none'));

[dicom_jobs, dicom_stats] = build_jobs_from_subject_list(dicom_input, 0, policy);
assert(dicom_stats.requested == 1 && dicom_stats.skipped == 0);
assert(length(dicom_jobs) == 1 && isempty(dicom_jobs(1).umap_fn));

% The two-argument API remains UMAP-required and must not silently adopt the
% new policy.
[legacy_jobs, legacy_stats] = build_jobs_from_subject_list(nifti_input, 1);
assert(isempty(legacy_jobs));
assert(legacy_stats.requested == 1 && legacy_stats.skipped == 1);

run_source = local_read(fullfile(root_dir, 'run_pseudo_CT.m'));
collect_source = local_read(fullfile(root_dir, 'src', 'core', 'collect_jobs.m'));
builder_source = local_read(fullfile(root_dir, 'src', 'core', ...
    'build_jobs_from_subject_list.m'));
gui_source = local_read(fullfile(root_dir, 'src', 'ui', 'load_mr_4_AC.m'));
promote_source = local_read(fullfile(root_dir, 'src', 'io', ...
    'pseudo_CT_promote_final_outputs.m'));
launchpad_source = local_read(fullfile(root_dir, 'src', 'launchpad', ...
    'batch_pseudo_CT_launchpad.m'));

assert(~isempty(strfind(collect_source, 'load_mr_4_AC(config.io_policy.gui)')));
assert(~isempty(strfind(builder_source, 'build_jobs_from_subject_list(subject_list, correct_aliasing, io_policy)')));
assert(~isempty(strfind(builder_source, 'if strcmp(io_policy.reference, ''none'')')));
assert(~isempty(strfind(builder_source, 'umap_fn = '''';')));
assert(~isempty(strfind(gui_source, 'case ''mprage-only''')));
assert(~isempty(strfind(gui_source, 'set(handles.load_umap_button, ''Visible'', ''Off'')')));
assert(~isempty(strfind(gui_source, 'if strcmp(handles.gui_mode, ''mprage-only'')')));
assert(isempty(strfind(run_source, 'local-mprage-only')));
assert(~isempty(strfind(run_source, ...
    'if strcmp(config.io_policy.output, ''nifti-and-dicom'')')));
save_creation = strfind(run_source, 'local_ensure_directory(save_dir);');
save_policy = strfind(run_source, ...
    'if strcmp(config.io_policy.output, ''nifti-and-dicom'')');
assert(length(save_creation) == 1 && save_policy(1) < save_creation(1));
assert(isempty(strfind(run_source, 'rmdir(save_dir')));
assert(isempty(strfind(run_source, 'delete(save_dir')));
assert(~isempty(strfind(run_source, 'Skipping DICOM output by profile policy.')));
assert(~isempty(strfind(launchpad_source, 'att_map.nii missing')));
assert(~isempty(strfind(launchpad_source, 'config.io_policy')) || ...
    ~isempty(strfind(run_source, 'config.io_policy.output')));
assert(~isempty(strfind(promote_source, 'stage_file = [destination_file ''.stage''];')));
assert(~isempty(strfind(promote_source, 'movefile(stage_specs{required_index, 1}')));

% Promotion success replaces the old map; a later run without a source map
% leaves that final map untouched and never removes historical output.
processing_dir = fullfile(test_dir, 'MR_PET');
temp_dir = fullfile(processing_dir, 'tmp');
mkdir(processing_dir);
mkdir(temp_dir);
local_write(fullfile(processing_dir, 'att_map.nii'), 'old map');
local_write(fullfile(temp_dir, 'att_map.nii'), 'new map');
local_write(fullfile(temp_dir, 'Pseudo_CT_AC_Version.txt'), 'version');
assert(pseudo_CT_promote_final_outputs(temp_dir, processing_dir, '', struct()) == 1);
assert(strcmp(local_read(fullfile(processing_dir, 'att_map.nii')), 'new map'));
assert(exist(fullfile(processing_dir, 'att_map.nii.stage'), 'file') ~= 2);
delete(fullfile(temp_dir, 'att_map.nii'));
assert(pseudo_CT_promote_final_outputs(temp_dir, processing_dir, '', struct()) == 0);
assert(strcmp(local_read(fullfile(processing_dir, 'att_map.nii')), 'new map'));

fprintf('MPRAGE-only profile tests passed: collection, GUI seams, policy gates, and promotion preservation.\n');
end

function text = local_read(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1, 'Could not read %s.', file_path);
text = fread(fid, inf, '*char')';
fclose(fid);
end

function local_write(file_path, text)
fid = fopen(file_path, 'w');
assert(fid ~= -1, 'Could not write %s.', file_path);
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
