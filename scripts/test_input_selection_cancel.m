function test_input_selection_cancel()
%TEST_INPUT_SELECTION_CANCEL X-close cancel contract regression (T005).
%   Headless: GUI abort is exercised through a path-shadowing
%   load_mr_4_AC stub plus static guards on the real sources. No interactive
%   clicking, no live pipeline runs. R2010b-compatible (char only).

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'config'), '-begin');
addpath(fullfile(root_dir, 'src', 'core'), '-begin');
addpath(fullfile(root_dir, 'src', 'ui'), '-begin');
addpath(fullfile(root_dir, 'src', 'io'), '-begin');

gui_source = local_read(fullfile(root_dir, 'src', 'ui', 'load_mr_4_AC.m'));
collect_source = local_read(fullfile(root_dir, 'src', 'core', 'collect_jobs.m'));

% --- Static: OutputFcn can never dot-index a non-struct handles ---
assert(~isempty(strfind(gui_source, 'load_mr_4_AC_CloseRequestFcn')));
assert(~isempty(strfind(gui_source, 'CloseRequestFcn')));
assert(~isempty(strfind(gui_source, 'uiresume')));
assert(~isempty(strfind(gui_source, 'if ~isstruct(handles)')));
assert(~isempty(strfind(gui_source, 'isfield(handles, ''mprage_fn'')')));
assert(~isempty(strfind(gui_source, 'ishghandle')));

% --- Static: collect_jobs cancel is type-safe, no blanket swallow ---
% Explicit cancel outputs (mprage_fn == 0) drive clean cancel; any GUI
% throw propagates with identity, never silent empty.
assert(isempty(strfind(collect_source, 'if mprage_fn == 0')));
assert(~isempty(strfind(collect_source, 'isnumeric(mprage_fn)')));
assert(~isempty(strfind(collect_source, 'isscalar(mprage_fn)')));
assert(isempty(strfind(collect_source, 'gui_aborted')));
assert(isempty(strfind(collect_source, 'catch')) || ~isempty(strfind(collect_source, 'rethrow')));

% --- Static: validation errors stay distinct from silent cancel ---
assert(~isempty(strfind(collect_source, 'validate_aliasing')));
assert(~isempty(strfind(collect_source, 'validate_recentering')));
assert(~isempty(strfind(collect_source, 'pseudo_CT:InvalidAliasing')) || ...
    ~isempty(strfind(collect_source, 'validate_aliasing(correct_aliasing)')));

% --- Functional: shadow the GUI with a deterministic stub ---
test_dir = tempname;
mkdir(test_dir);
dir_cleanup = onCleanup(@() local_cleanup(test_dir)); %#ok<NASGU>
mprage_file = fullfile(test_dir, 'mprage.nii');
ute_file = fullfile(test_dir, 'ute.nii');
umap_file = fullfile(test_dir, 'umap.nii');
local_write(mprage_file, 'MPRAGE-FIXTURE');
local_write(ute_file, 'UTE-FIXTURE');
local_write(umap_file, 'UMAP-FIXTURE');

stub_dir = fullfile(test_dir, 'stub');
mkdir(stub_dir);
local_write(fullfile(stub_dir, 'load_mr_4_AC.m'), local_stub_text());
old_path = path();
addpath(stub_dir, '-begin');
clear('load_mr_4_AC');
rehash;
stub_cleanup = onCleanup(@() local_restore_path(old_path)); %#ok<NASGU>
old_behavior = getenv('PSEUDOCT_TEST_GUI_BEHAVIOR');
old_valid = getenv('PSEUDOCT_TEST_VALID_MPRAGE');
old_valid_ute = getenv('PSEUDOCT_TEST_VALID_UTE');
old_valid_umap = getenv('PSEUDOCT_TEST_VALID_UMAP');
env_cleanup = onCleanup(@() local_restore_env(old_behavior, ...
    old_valid, old_valid_ute, old_valid_umap)); %#ok<NASGU>
setenv('PSEUDOCT_TEST_VALID_MPRAGE', mprage_file);
setenv('PSEUDOCT_TEST_VALID_UTE', ute_file);
setenv('PSEUDOCT_TEST_VALID_UMAP', umap_file);

policy_none.reference = 'none';
policy_none.output = 'nifti-only';
policy_none.gui = 'mprage-only';
config_none = struct('aliasing_default', 1, ...
    'recenter_before_normalization', 'No', 'io_policy', policy_none);

policy_umap.reference = 'umap-required';
policy_umap.output = 'nifti-and-dicom';
policy_umap.gui = 'mMR';
config_umap = struct('aliasing_default', 1, ...
    'recenter_before_normalization', 'No', 'io_policy', policy_umap);

% Valid outputs are accepted (mprage-only and umap-required policies).
setenv('PSEUDOCT_TEST_GUI_BEHAVIOR', 'valid');
[valid_jobs, valid_stats] = collect_jobs(config_none);
assert(length(valid_jobs) == 1);
assert(strcmp(valid_jobs(1).mprage_fn, mprage_file));
assert(valid_stats.requested == 1 && valid_stats.skipped == 0);
setenv('PSEUDOCT_TEST_GUI_BEHAVIOR', 'valid-full');
[full_jobs, full_stats] = collect_jobs(config_umap);
assert(length(full_jobs) == 1);
assert(strcmp(full_jobs(1).mprage_fn, mprage_file));
assert(full_stats.requested == 1 && full_stats.skipped == 0);

% Explicit cancel -> pre-initialized empty jobs + zeroed stats, no paths.
setenv('PSEUDOCT_TEST_GUI_BEHAVIOR', 'cancel');
[cancel_jobs, cancel_stats] = collect_jobs(config_none);
assert(isempty(cancel_jobs));
assert(cancel_stats.requested == 0 && cancel_stats.skipped == 0);
assert(isempty(cancel_stats.skipped_subjects));

% Partial cancel (pre- or partial-selection X-close) is clean cancel.
setenv('PSEUDOCT_TEST_GUI_BEHAVIOR', 'partial');
[partial_jobs, partial_stats] = collect_jobs(config_none);
assert(isempty(partial_jobs));
assert(partial_stats.requested == 0 && partial_stats.skipped == 0);

% GUI abort that throws keeps identity, never silent empty (narrowed catch).
setenv('PSEUDOCT_TEST_GUI_BEHAVIOR', 'throw');
threw = false;
throw_id = '';
try
    collect_jobs(config_none);
catch ME
    threw = true;
    throw_id = ME.identifier;
end
assert(threw);
assert(strcmp(throw_id, 'test_input_selection_cancel:GuiAbort'));

% Invalid aliasing/recentering stay validation errors, never silent cancel.
invalid_aliasing = false;
try
    collect_jobs(config_none, mprage_file, 'bad-flag');
catch ME
    invalid_aliasing = strcmp(ME.identifier, 'pseudo_CT:InvalidAliasing');
end
assert(invalid_aliasing);
invalid_recentering = false;
try
    collect_jobs(config_none, mprage_file, 1, 'maybe');
catch ME
    invalid_recentering = strcmp(ME.identifier, 'pseudo_CT:InvalidRecentering');
end
assert(invalid_recentering);

setenv('PSEUDOCT_TEST_GUI_BEHAVIOR', old_behavior);
setenv('PSEUDOCT_TEST_VALID_MPRAGE', old_valid);
setenv('PSEUDOCT_TEST_VALID_UTE', old_valid_ute);
setenv('PSEUDOCT_TEST_VALID_UMAP', old_valid_umap);
path(old_path);
clear('load_mr_4_AC');
rehash;

fprintf('Input-selection cancel tests passed: valid accepted, cancel/partial empty, throw rethrows, invalid distinct.\n');
end

function text = local_stub_text()
lines = {
    'function [mprage_fn, ute_fn, umap_fn, correct_aliasing, recenter_before_normalization] = load_mr_4_AC(varargin)'
    'mode = getenv(''PSEUDOCT_TEST_GUI_BEHAVIOR'');'
    'if strcmp(mode, ''valid-full'')'
    '    mprage_fn = getenv(''PSEUDOCT_TEST_VALID_MPRAGE'');'
    '    ute_fn = getenv(''PSEUDOCT_TEST_VALID_UTE'');'
    '    umap_fn = getenv(''PSEUDOCT_TEST_VALID_UMAP'');'
    '    correct_aliasing = 1;'
    '    recenter_before_normalization = 0;'
    'elseif strcmp(mode, ''valid'')'
    '    mprage_fn = getenv(''PSEUDOCT_TEST_VALID_MPRAGE'');'
    '    ute_fn = '''';'
    '    umap_fn = '''';'
    '    correct_aliasing = 1;'
    '    recenter_before_normalization = 0;'
    'elseif strcmp(mode, ''throw'')'
    '    error(''test_input_selection_cancel:GuiAbort'', ''Simulated X-close abort.'');'
    'elseif strcmp(mode, ''partial'')'
    '    mprage_fn = 0;'
    '    ute_fn = '''';'
    '    umap_fn = '''';'
    '    correct_aliasing = 0;'
    '    recenter_before_normalization = 0;'
    'else'
    '    mprage_fn = 0;'
    '    ute_fn = 0;'
    '    umap_fn = 0;'
    '    correct_aliasing = 0;'
    '    recenter_before_normalization = 0;'
    'end'
    'end'
    };
text = '';
for ii = 1:length(lines)
    text = [text lines{ii} char(10)]; %#ok<AGROW>
end
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

function local_restore_path(old_path)
clear('load_mr_4_AC');
path(old_path);
try
    rehash;
catch %#ok<CTCH>
end
end

function local_restore_env(old_behavior, old_valid, old_ute, old_umap)
setenv('PSEUDOCT_TEST_GUI_BEHAVIOR', old_behavior);
setenv('PSEUDOCT_TEST_VALID_MPRAGE', old_valid);
setenv('PSEUDOCT_TEST_VALID_UTE', old_ute);
setenv('PSEUDOCT_TEST_VALID_UMAP', old_umap);
end
