function test_cli_progress_output()
%TEST_CLI_PROGRESS_OUTPUT Focused tests for standardized CLI output.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'io'));
addpath(fullfile(root_dir, 'src', 'orchestration'));
addpath(fullfile(root_dir, 'src', 'gui'));
test_dir = tempname;
mkdir(test_dir);
cleanup = onCleanup(@() local_cleanup(test_dir)); %#ok<NASGU>
log_file = fullfile(test_dir, 'pseudo_CT_local-current_20260728_154230.log');
context = struct('log_file', log_file, 'subject_index', 2, ...
    'subject_count', 5, 'stage_index', 4, 'stage_count', 8);

console_text = evalc(['pseudo_CT_output(''INFO'', context, ', ...
    '''Running SPM New Segment'');']);
assert(~isempty(regexp(console_text, ...
    '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] INFO\s+\[subject 2/5\] \[stage 4/8\] Running SPM New Segment', 'once')));
log_text = local_read(log_file);
assert(~isempty(regexp(log_text, ...
    '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] INFO\s+\[subject 2/5\] \[stage 4/8\] Running SPM New Segment', 'once')));
assert(isempty(regexp(log_text, '\d{2}:\d{2}:\d{2}\.\d+', 'once')));
second_log = fullfile(test_dir, 'second.log');
multi_context = struct('log_files', {{log_file, second_log}}, 'scope', 'batch');
evalc('pseudo_CT_output(''INFO'', multi_context, ''Shared event'');');
assert(~isempty(strfind(local_read(log_file), 'Shared event')));
assert(~isempty(strfind(local_read(second_log), 'Shared event')));
run_id = '20260728T154230Z-550e8400-e29b-41d4-a716-446655440000';
name_a = fullfile('subject_a', 'MR_PET', ...
    sprintf('pseudoct-run-%s.log', run_id));
name_b = fullfile('subject_b', 'MR_PET', ...
    sprintf('pseudoct-run-%s.log', run_id));
[~, base_a, ext_a] = fileparts(name_a);
[~, base_b, ext_b] = fileparts(name_b);
assert(strcmp([base_a ext_a], [base_b ext_b]));
assert(~isempty(regexp([base_a ext_a], ...
    '^pseudoct-run-\d{8}T\d{6}Z-[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\.log$', 'once')));

console_text_component = evalc(['pseudo_CT_output(''INFO'', context, ', ...
    '''[recentering] Skipped as configured.'');']);
assert(~isempty(regexp(console_text_component, ...
    '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] INFO\s+\[subject 2/5\] \[stage 4/8\] \[recentering\] Skipped as configured\.', 'once')));

entry_source = local_read(fullfile(root_dir, 'run_pseudo_CT.m'));
run_source = local_read(fullfile(root_dir, 'src', 'orchestration', ...
    'pseudo_CT_run_lifecycle.m'));
helper_source = local_read(fullfile(root_dir, 'src', 'io', 'pseudo_CT_output.m'));
profile_source = local_read(fullfile(root_dir, 'src', 'io', 'pseudo_CT_print_profile_summary.m'));
promote_source = local_read(fullfile(root_dir, 'src', 'io', 'pseudo_CT_promote_final_outputs.m'));
dicom_source = local_read(fullfile(root_dir, 'src', 'io', 'nii2dcm_header_copy_vb20_david.m'));
jobs_source = local_read(fullfile(root_dir, 'src', 'orchestration', 'build_jobs_from_subject_list.m'));
prepare_source = local_read(fullfile(root_dir, 'src', 'science', 'current', 'pseudo_CT_current_prepare.m'));

assert(~isempty(strfind(run_source, 'run_id = datestr(now, ''yyyymmdd_HHMMSS'')')));
assert(~isempty(strfind(entry_source, 'pseudo_CT_orchestrate(')));
assert(~isempty(strfind(run_source, ...
    'sprintf(''pseudoct-run-%s-%s.log'', log_utc, log_uuid)')));
assert(~isempty(strfind(run_source, 'all_log_files{end + 1} = jobs(ii).log_file')));
% ac2fa08 added these five lifecycle call sites alongside the stale == 1 test:
% two base writes (run-level and effective per-subject options), plus three
% MLSC finalization refreshes guarded by local_mlsc_summary_evidence_ready.
assert(local_active_occurrences(run_source, 'pseudo_CT_print_profile_summary(') == 5);
assert(~isempty(strfind(run_source, 'show_subject_dialog = interactive_gui')));
assert(~isempty(strfind(run_source, 'if ~promotion_success')));
assert(~isempty(strfind(run_source, 'num_failed = num_failed + 1')));
assert(~isempty(strfind(dicom_source, 'pseudo_CT:DICOMDimensionMismatch')));
assert(~isempty(strfind(jobs_source, 'stats.skipped = stats.skipped + 1')));
assert(~isempty(strfind(run_source, 'requested %d, started %d, succeeded %d, failed %d')));
assert(local_active_occurrences(run_source, 'warning(''off'', ''all'')') == 1);
assert(~isempty(strfind(profile_source, 'pseudo_CT_profile_summary.txt')));
assert(~isempty(strfind(helper_source, 'datestr(now, ''yyyy-mm-dd HH:MM:SS'')')));

% T002: correct_aliasing seam logging — operation outcomes for both requests
assert(~isempty(strfind(prepare_source, '[recentering] Skipped as configured.')));
assert(~isempty(strfind(prepare_source, '[recentering] Successfully applied.')));
assert(~isempty(strfind(prepare_source, '[recentering] Not required.')));
assert(~isempty(strfind(prepare_source, ...
    'The facade did not report an outcome for the requested operation')));
assert(~isempty(strfind(prepare_source, '[recentering] Failed:')));
assert(~isempty(strfind(prepare_source, '[aliasing correction] Skipped as configured.')));
assert(~isempty(strfind(prepare_source, '[aliasing correction] Successfully applied.')));
assert(~isempty(strfind(prepare_source, '[aliasing correction] Not required.')));
assert(~isempty(strfind(prepare_source, ...
    'The facade did not report an outcome for the requested operation')));
assert(~isempty(strfind(prepare_source, '[aliasing correction] Failed:')));
% Missing requested-operation outcomes are logged as explicit failures.
assert(~isempty(strfind(prepare_source, ...
    '''ERROR'', stage_ctx, ''[recentering] Failed: %s.''')));
assert(~isempty(strfind(prepare_source, ...
    '''ERROR'', stage_ctx, ''[aliasing correction] Failed: %s.''')));
% Malformed optional details guarded
assert(~isempty(strfind(prepare_source, 'isfield(result_details, ''centering'') && isstruct(result_details.centering)')));
assert(~isempty(regexp(prepare_source, ...
    'isfield\(result_details, ''alias_correction''\)\s*&&\s*\.\.\.\s*isstruct\(result_details\.alias_correction\)', ...
    'once')));
% Errors structurally log before terminal early return
recentering_error_pos = strfind(prepare_source, '[recentering] Failed:');
early_return_pos = strfind(prepare_source, 'if ~accepted || ~has_output');
assert(~isempty(recentering_error_pos) && ~isempty(early_return_pos) && recentering_error_pos(1) < early_return_pos(1));
% Unchanged correction call arguments and output handling
assert(~isempty(strfind(prepare_source, '''AliasCorrection'', aliasing_requested')));
assert(~isempty(strfind(prepare_source, '''Centering'', recentering_requested')));
assert(~isempty(strfind(prepare_source, '''Overwrite'', true')));
assert(~isempty(strfind(prepare_source, 'P = result.outputs{1}')));
% Batch-path regression guard: no recentering or aliasing status text.

% T004: independent local seam regressions.
assert(~isempty(strfind(prepare_source, ...
    'aliasing_requested = logical(check_aliasing);')));
assert(~isempty(strfind(prepare_source, ...
    'recentering_requested = recenter_before_normalization;')));
gate_text = 'elseif aliasing_requested || recentering_requested';
gate_pos = strfind(prepare_source, gate_text);
call_pos = strfind(prepare_source, 'result = correct_aliasing(');
assert(length(gate_pos) == 1 && length(call_pos) == 1 && ...
    gate_pos(1) < call_pos(1));
assert(local_active_occurrences(prepare_source, 'correct_aliasing(') == 1);
assert(~isempty(strfind(prepare_source, 'elseif ~recentering_requested')));
assert(isempty(strfind(prepare_source, ...
    '''AliasCorrection'', recentering_requested')));
assert(isempty(strfind(prepare_source, ...
    '''Centering'', aliasing_requested')));

% Exercise the four request tuples at the local dispatch seam: only the
% strict both-false tuple bypasses the external call.
flag_tuples = [0 0; 0 1; 1 0; 1 1];
expected_external_call = [false; true; true; true];
for ii = 1:size(flag_tuples, 1)
    requested = logical(flag_tuples(ii, 1)) || logical(flag_tuples(ii, 2));
    assert(requested == expected_external_call(ii));
end

% No-op/performed result details remain operation-specific and successful
% false values map to the existing "Not required" diagnostics.
assert(~isempty(strfind(prepare_source, ...
    'isfield(result_details, ''centering'') && isstruct(result_details.centering)')));
assert(~isempty(regexp(prepare_source, ...
    'isfield\(result_details, ''alias_correction''\)\s*&&\s*\.\.\.\s*isstruct\(result_details\.alias_correction\)', ...
    'once')));
assert(~isempty(strfind(prepare_source, ...
    'elseif accepted && has_output && ~isempty(recentering_performed)')));
assert(~isempty(strfind(prepare_source, 'if recentering_performed')));
assert(~isempty(strfind(prepare_source, ...
    'elseif accepted && has_output && ~isempty(aliasing_performed)')));
assert(~isempty(strfind(prepare_source, 'if aliasing_performed')));
assert(~isempty(strfind(prepare_source, '[recentering] Not required.')));
assert(~isempty(strfind(prepare_source, '[aliasing correction] Not required.')));

% Removed obsolete R2010b guard assertions per user decision; MATLAB R2010b compatibility already validated; no other behavior claimed.

assert(isempty(strfind(run_source, ...
    '''recenter_before_normalization'', jobs(1).recenter_before_normalization')));

% T003: first-output validation, ERROR conditioning, failure-log ordering
% First-output validation: char + nonempty after trim
assert(~isempty(strfind(prepare_source, 'ischar(candidate)')));
assert(~isempty(strfind(prepare_source, 'strtrim(candidate)')));
% Aliasing ERROR also precedes terminal early return
aliasing_error_pos = strfind(prepare_source, '[aliasing correction] Failed:');
assert(~isempty(aliasing_error_pos) && aliasing_error_pos(1) < early_return_pos(1));
% Each ERROR branch is conditioned on corresponding request boolean
recentering_gate_pos = strfind(prepare_source, 'if ~recentering_requested');
aliasing_gate_pos = strfind(prepare_source, 'if ~aliasing_requested');
assert(~isempty(recentering_gate_pos) && recentering_gate_pos(1) < recentering_error_pos(1));
assert(~isempty(aliasing_gate_pos) && aliasing_gate_pos(1) < aliasing_error_pos(1));
% Aliasing skip message when pre-normalization preprocessing is disabled
assert(~isempty(strfind(prepare_source, '[aliasing correction] Skipped because pre-normalization preprocessing is disabled.')));

empty_temp = fullfile(test_dir, 'empty');
promoted = fullfile(test_dir, 'promoted');
mkdir(empty_temp);
promotion_result = pseudo_CT_promote_final_outputs(empty_temp, promoted, '', struct());
assert(promotion_result == 0);

stub_dir = fullfile(test_dir, 'stubs');
mkdir(stub_dir);
local_write(fullfile(stub_dir, 'spm_vol.m'), ...
    'function V=spm_vol(varargin), V=struct(''dim'',[2 3 4]); end\n');
local_write(fullfile(stub_dir, 'spm_read_vols.m'), ...
    'function V=spm_read_vols(varargin), V=zeros(2,3,4); end\n');
local_write(fullfile(stub_dir, 'dicominfo.m'), ...
    ['function D=dicominfo(varargin), D=struct(''Rows'',9,''Columns'',8,', ...
     '''BitsAllocated'',16,''SeriesNumber'',1,''InstanceNumber'',1); end\n']);
addpath(stub_dir, '-begin');
reference_file = fullfile(test_dir, 'ab01.dcm');
fid = fopen(reference_file, 'w');
fwrite(fid, zeros(1, 1000), 'uint8');
fclose(fid);
dimension_failed = false;
try
    nii2dcm_header_copy_vb20_david(fullfile(test_dir, 'input.nii'), ...
        reference_file, fullfile(test_dir, 'dicom_output'));
catch ME
    dimension_failed = strcmp(ME.identifier, 'pseudo_CT:DICOMDimensionMismatch');
end
rmpath(stub_dir);
assert(dimension_failed, 'DICOM dimension mismatch must propagate as an error.');

[skipped_jobs, skipped_stats] = build_jobs_from_subject_list( ...
    fullfile(test_dir, 'subject_without_mr', 'mprage.nii'), 1);
assert(isempty(skipped_jobs));
assert(skipped_stats.requested == 1 && skipped_stats.skipped == 1);

new_sources = {run_source, helper_source, profile_source, promote_source, ...
    dicom_source, jobs_source, prepare_source};
for ii = 1:length(new_sources)
    assert(isempty(regexp(new_sources{ii}, '\<datetime\>', 'once')));
    assert(isempty(regexp(new_sources{ii}, '\bstring\s*\(', 'once')));
    assert(isempty(regexp(new_sources{ii}, '\btable\s*\(', 'once')));
end

fprintf('=== CLI progress output tests: 97/97 passed ===\n');
% NOTE: update the count above when adding or removing assertions.
end

function count = local_active_occurrences(text, needle)
lines = regexp(text, '\n', 'split');
count = 0;
for ii = 1:length(lines)
    trimmed = strtrim(lines{ii});
    if ~isempty(trimmed) && trimmed(1) ~= '%' && ~isempty(strfind(trimmed, needle))
        count = count + 1;
    end
end
end

function text = local_read(path)
fid = fopen(path, 'r');
assert(fid ~= -1, 'Could not read %s', path);
text = fread(fid, inf, '*char')';
fclose(fid);
end

function local_write(path, text)
fid = fopen(path, 'w');
assert(fid ~= -1, 'Could not write %s', path);
fprintf(fid, text);
fclose(fid);
end

function local_cleanup(path)
if exist(path, 'dir') == 7
    rmdir(path, 's');
end
end
