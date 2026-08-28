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
assert(isfield(nifti_jobs, 'correct_aliasing'));
assert(isfield(nifti_jobs, 'recenter_before_normalization'));
assert(nifti_jobs(1).correct_aliasing == true);
assert(nifti_jobs(1).recenter_before_normalization == false);
assert(strcmp(nifti_jobs(1).io_policy.reference, 'none'));

[dicom_jobs, dicom_stats] = build_jobs_from_subject_list(dicom_input, 0, policy);
assert(dicom_stats.requested == 1 && dicom_stats.skipped == 0);
assert(length(dicom_jobs) == 1 && isempty(dicom_jobs(1).umap_fn));
assert(dicom_jobs(1).correct_aliasing == false);
assert(dicom_jobs(1).recenter_before_normalization == false);

% The optional fourth argument carries an independent recentering request.
[extended_jobs, extended_stats] = build_jobs_from_subject_list( ...
    nifti_input, 0, policy, 'Yes');
assert(extended_stats.requested == 1 && extended_stats.skipped == 0);
assert(length(extended_jobs) == 1);
assert(extended_jobs(1).correct_aliasing == false);
assert(extended_jobs(1).recenter_before_normalization == true);

% Explicit-list collection uses profile defaults and preserves independent
% overrides without opening the GUI.
config = struct();
config.aliasing_default = 1;
config.recenter_before_normalization = 'Yes';
config.io_policy = policy;
[configured_jobs, configured_stats] = collect_jobs(config, nifti_input);
assert(configured_stats.requested == 1 && configured_stats.skipped == 0);
assert(length(configured_jobs) == 1);
assert(configured_jobs(1).correct_aliasing == true);
assert(configured_jobs(1).recenter_before_normalization == true);
[override_jobs, override_stats] = collect_jobs(config, nifti_input, 0, 'No');
assert(override_stats.requested == 1 && override_stats.skipped == 0);
assert(length(override_jobs) == 1);
assert(override_jobs(1).correct_aliasing == false);
assert(override_jobs(1).recenter_before_normalization == false);

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

assert(~isempty(strfind(collect_source, ...
    'load_mr_4_AC(config.io_policy.gui, config)')));
assert(~isempty(strfind(builder_source, ...
    'build_jobs_from_subject_list(subject_list, correct_aliasing, ...')));
assert(~isempty(strfind(collect_source, ...
    'config.io_policy, recenter_before_normalization);')));
assert(~isempty(strfind(builder_source, 'if strcmp(io_policy.reference, ''none'')')));
assert(~isempty(strfind(builder_source, 'umap_fn = '''';')));
assert(~isempty(strfind(builder_source, ...
    'function [jobs, stats] = build_jobs_from_subject_list(subject_list, correct_aliasing, ...')));
assert(~isempty(strfind(gui_source, 'case ''mprage-only''')));
assert(~isempty(strfind(gui_source, 'case 0')));
assert(~isempty(strfind(gui_source, 'case ''mMR''')));
assert(~isempty(strfind(gui_source, 'set(handles.load_umap_button, ''Visible'', ''Off'')')));
assert(~isempty(strfind(gui_source, 'if strcmp(handles.gui_mode, ''mprage-only'')')));
assert(~isempty(strfind(gui_source, 'aliasing_default = 1')));
assert(~isempty(strfind(gui_source, 'recentering_default = 0')));
assert(~isempty(strfind(gui_source, 'gui_defaults = varargin{2}')));
assert(~isempty(strfind(gui_source, ...
    'elseif isfield(gui_defaults, ''correct_aliasing'')')));
assert(~isempty(strfind(gui_source, ...
    'isfield(gui_defaults, ''recenter_before_normalization'')')));
assert(~isempty(strfind(gui_source, ...
    'handles.correct_aliasing = normalize_gui_flag(aliasing_default, true)')));
assert(~isempty(strfind(gui_source, ...
    'handles.recenter_before_normalization = normalize_gui_flag(recentering_default, false)')));
assert(~isempty(strfind(gui_source, 'varargout{1} = handles.mprage_fn;')));
assert(~isempty(strfind(gui_source, 'varargout{2} = handles.ute_fn;')));
assert(~isempty(strfind(gui_source, 'varargout{3} = handles.umap_fn;')));
assert(~isempty(strfind(gui_source, 'varargout{4} = handles.correct_aliasing;')));
assert(~isempty(strfind(gui_source, 'if nargout > 4')));
assert(~isempty(strfind(gui_source, ...
    'varargout{5} = handles.recenter_before_normalization;')));
assert(~isempty(strfind(gui_source, 'function recentering_button_Callback')));
assert(~isempty(strfind(gui_source, ...
    'handles.recenter_before_normalization = logical(get(hObject,''Value''))')));
assert(~isempty(strfind(gui_source, 'handles.correct_aliasing = 0;')));
assert(~isempty(strfind(gui_source, 'handles.recenter_before_normalization = 0;')));
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

% The edited GUIDE binary must remain readable and contain one stable
% recentering control alongside the existing aliasing control.  Keep the
% figure invisible and close it on every assertion path.
fig_path = fullfile(root_dir, 'src', 'ui', 'load_mr_4_AC.fig');
fig_handle = openfig(fig_path, 'new', 'invisible');
try
    assert(ishandle(fig_handle));
    assert(strcmp(get(fig_handle, 'Type'), 'figure'));
    recentering_controls = findobj(fig_handle, 'Tag', 'recentering_button');
    aliasing_controls = findobj(fig_handle, 'Tag', 'aliasing_button');
    assert(length(recentering_controls) == 1);
    assert(length(aliasing_controls) == 1);
    assert(strcmp(get(recentering_controls, 'Style'), 'checkbox'));
    assert(strcmp(get(aliasing_controls, 'Style'), 'checkbox'));
    assert(get(recentering_controls, 'Value') == 0);
    assert(strcmp(get(recentering_controls, 'String'), ...
        'Recenter MPRAGE before normalization'));
    assert(get(aliasing_controls, 'Value') == 0);
    assert(strcmp(get(aliasing_controls, 'String'), ...
        'Auto-correct Nose-Neck aliasing (if required)'));
    recentering_callback = get(recentering_controls, 'Callback');
    if ischar(recentering_callback)
        recentering_callback_text = recentering_callback;
    elseif isa(recentering_callback, 'function_handle')
        recentering_callback_text = func2str(recentering_callback);
    else
        recentering_callback_text = '';
    end
    assert(~isempty(strfind(recentering_callback_text, ...
        'load_mr_4_AC')));
    assert(~isempty(strfind(recentering_callback_text, ...
        'recentering_button_Callback')));
    aliasing_callback = get(aliasing_controls, 'Callback');
    if ischar(aliasing_callback)
        aliasing_callback_text = aliasing_callback;
    elseif isa(aliasing_callback, 'function_handle')
        aliasing_callback_text = func2str(aliasing_callback);
    else
        aliasing_callback_text = '';
    end
    assert(~isempty(strfind(aliasing_callback_text, 'load_mr_4_AC')));
    assert(~isempty(strfind(aliasing_callback_text, ...
        'aliasing_button_Callback')));

    assert(isequal(get(aliasing_controls, 'Parent'), ...
        get(recentering_controls, 'Parent')));
    aliasing_units = get(aliasing_controls, 'Units');
    recentering_units = get(recentering_controls, 'Units');
    assert(strcmp(aliasing_units, recentering_units));
    assert(strcmp(aliasing_units, 'characters'));

    aliasing_position = get(aliasing_controls, 'Position');
    recentering_position = get(recentering_controls, 'Position');
    assert(isequal(aliasing_position([1 3 4]), ...
        recentering_position([1 3 4])));
    assert(aliasing_position(2) > recentering_position(2));
    assert(isequal(aliasing_position(2) - recentering_position(2) - ...
        recentering_position(4), 0.5));

    style_properties = {'FontUnits'; 'FontName'; 'FontSize'; 'FontWeight'; ...
        'FontAngle'; 'HorizontalAlignment'; 'ForegroundColor'; ...
        'BackgroundColor'};
    for ii = 1:length(style_properties)
        assert(isequal(get(aliasing_controls, style_properties{ii}), ...
            get(recentering_controls, style_properties{ii})));
    end
catch ME
    local_close_figure(fig_handle);
    rethrow(ME);
end
local_close_figure(fig_handle);

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

function local_close_figure(fig_handle)
if ~isempty(fig_handle) && ishandle(fig_handle)
    close(fig_handle);
end
end
