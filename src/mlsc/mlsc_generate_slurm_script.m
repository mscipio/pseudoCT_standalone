function artifact = mlsc_generate_slurm_script(subject, config, runtime)
%MLSC_GENERATE_SLURM_SCRIPT Generate one safe MLSC Slurm job script.
%   ARTIFACT = MLSC_GENERATE_SLURM_SCRIPT(SUBJECT, CONFIG, RUNTIME) returns
%   credential-free script text and, when RUNTIME contains ACCOUNT and
%   SCRIPT_PATH, a safely quoted per-subject sbatch command.  The subject
%   input is expected to have been written by MATLAB into the existing shared
%   subject temporary directory.  No scheduler, network, or file staging is
%   performed by this function.
%
%   All variable paths are represented as POSIX shell single-quoted values;
%   embedded single quotes are safely split and re-opened.  The batch shell
%   performs only normal filesystem cp operations between shared storage and
%   node-local $TMPDIR.  Slurm stdout and stderr are retained in the shared
%   subject temp using the job-ID patterns pseudoCT_mlsc_%j.out/.err.
%
%   The batch shell also appends tiny deterministic T001 progress records to
%   the exact per-submission shared "$shared_temp/.mlsc_progress_<id>" file
%   around the existing work, where <id> is the non-secret submission
%   correlation identity passed explicitly in RUNTIME (RUNTIME.
%   submission_correlation_id).  Without that identity the legacy shared
%   "$shared_temp/.mlsc_progress" name is used for direct generation only.
%   Each write is best-effort append-only under umask 077 and can never fail
%   the job.  Records and the correlation suffix contain only fixed
%   stage|state literals and [A-Za-z0-9_.-], never paths, accounts,
%   credentials, or SSH values.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 3 || isempty(runtime)
    runtime = struct();
end
preflight = mlsc_preflight(subject, config, runtime);
mlsc = config.mlsc;

shared_input = local_subject_value(subject, {'shared_input'; 'seed_nii'});
shared_temp = local_subject_value(subject, {'shared_temp'; 'temp_dir'});
shared_temp = local_strip_trailing_separators(shared_temp);
check_aliasing = preflight.check_aliasing;

input_name = preflight.input_name;
normalized_name = preflight.normalized_name;
needs_normalization = preflight.needs_normalization;

q_shared_input = local_shell_quote(shared_input);
q_shared_temp = local_shell_quote(shared_temp);
q_input_name = local_shell_quote(input_name);
q_normalized_name = local_shell_quote(normalized_name);
q_freesurfer_env = local_shell_quote(mlsc.freesurfer_env);
q_runner = local_shell_quote(mlsc.runner);
q_mcr_root = local_shell_quote(mlsc.mcr_root);
q_batch_templates = local_shell_quote(mlsc.batch_templates);
q_defaults_mat = local_shell_quote(mlsc.defaults_mat);
stdout_log_path = fullfile(shared_temp, 'pseudoCT_mlsc_%j.out');
stderr_log_path = fullfile(shared_temp, 'pseudoCT_mlsc_%j.err');
q_stdout_log_path = local_shell_quote(stdout_log_path);
q_stderr_log_path = local_shell_quote(stderr_log_path);

lines = {};
lines{end + 1} = ['#!' mlsc.shell];
lines{end + 1} = ['#SBATCH --partition=' mlsc.partition];
lines{end + 1} = ['#SBATCH --nodes=' num2str(mlsc.nodes)];
lines{end + 1} = ['#SBATCH --ntasks=' num2str(mlsc.ntasks)];
lines{end + 1} = ['#SBATCH --cpus-per-task=' num2str(mlsc.cpus_per_task)];
lines{end + 1} = ['#SBATCH --mem=' mlsc.memory];
lines{end + 1} = ['#SBATCH --time=' mlsc.time];
lines{end + 1} = ['#SBATCH --output=' q_stdout_log_path];
lines{end + 1} = ['#SBATCH --error=' q_stderr_log_path];
lines{end + 1} = '';
lines{end + 1} = 'set -euo pipefail';
lines{end + 1} = 'umask 077';
lines{end + 1} = ['shared_input=' q_shared_input];
lines{end + 1} = ['shared_temp=' q_shared_temp];
lines{end + 1} = ['input_name=' q_input_name];
lines{end + 1} = ['normalized_name=' q_normalized_name];
[progress_filename, progress_correlation_id] = ...
    local_progress_selection(runtime);
lines{end + 1} = ['progress_file="$shared_temp/' progress_filename '"'];
lines{end + 1} = 'mlsc_record_progress() {';
lines{end + 1} = '    (umask 077; printf ''%s\n'' "$1" >> "$progress_file") || true';
lines{end + 1} = '}';
lines{end + 1} = 'if [ -z "${TMPDIR:-}" ]; then';
lines{end + 1} = '    printf ''MLSC job requires node-local TMPDIR.\n'' >&2';
lines{end + 1} = '    exit 71';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -d "$TMPDIR" ] || [ ! -w "$TMPDIR" ]; then';
lines{end + 1} = '    printf ''Node-local TMPDIR is unavailable or unwritable.\n'' >&2';
lines{end + 1} = '    exit 71';
lines{end + 1} = 'fi';
lines{end + 1} = 'case "$TMPDIR" in';
lines{end + 1} = '    "$shared_temp"|"$shared_temp"/*)';
lines{end + 1} = '        printf ''TMPDIR must be node-local, not the shared subject temp.\n'' >&2';
lines{end + 1} = '        exit 71';
lines{end + 1} = '        ;;';
lines{end + 1} = 'esac';
lines{end + 1} = 'if [ ! -r "$shared_input" ]; then';
lines{end + 1} = '    printf ''Shared MLSC input is not readable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -d "$shared_temp" ] || [ ! -w "$shared_temp" ]; then';
lines{end + 1} = '    printf ''Shared MLSC subject temp is unavailable or unwritable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'shared_probe="$shared_temp/.mlsc_preflight.$$"';
lines{end + 1} = 'shared_probe_created=0';
lines{end + 1} = 'cleanup_shared_probe() {';
lines{end + 1} = '    if [ "$shared_probe_created" -eq 1 ]; then';
lines{end + 1} = '        rm -f -- "$shared_probe"';
lines{end + 1} = '    fi';
lines{end + 1} = '}';
lines{end + 1} = 'trap cleanup_shared_probe EXIT';
lines{end + 1} = 'if ! (umask 077; set -C; : > "$shared_probe"); then';
lines{end + 1} = '    printf ''Shared MLSC subject temp failed its write preflight.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'shared_probe_created=1';
lines{end + 1} = 'local_input="$TMPDIR/$input_name"';
lines{end + 1} = 'local_normalized="$TMPDIR/$normalized_name"';
lines{end + 1} = 'MCR_CACHE_ROOT="$TMPDIR/mcr_cache"';
lines{end + 1} = 'export MCR_CACHE_ROOT';
lines{end + 1} = ': "${SLURM_CPUS_PER_TASK:?SLURM_CPUS_PER_TASK is required}"';
lines{end + 1} = 'export OMP_NUM_THREADS="$SLURM_CPUS_PER_TASK"';
lines{end + 1} = 'export MKL_NUM_THREADS="$SLURM_CPUS_PER_TASK"';
lines{end + 1} = 'mkdir -p -- "$MCR_CACHE_ROOT"';
lines{end + 1} = 'cp -- "$shared_input" "$local_input"';
lines{end + 1} = 'cd "$TMPDIR"';
lines{end + 1} = 'mlsc_record_progress ''stage_in|done''';

if needs_normalization
    tcsh_program = 'source "$MLSC_FREESURFER_ENV"; mri_normalize "$TMPDIR/$MLSC_INPUT_NAME" "$TMPDIR/$MLSC_NORMALIZED_NAME"';
    lines{end + 1} = 'mlsc_record_progress ''normalize|start''';
    lines{end + 1} = ['env -u LD_LIBRARY_PATH MLSC_FREESURFER_ENV=' q_freesurfer_env ' MLSC_INPUT_NAME=' q_input_name ' MLSC_NORMALIZED_NAME=' q_normalized_name ' tcsh -f -c ''' tcsh_program ''''];
    lines{end + 1} = 'mlsc_record_progress ''normalize|done''';
    runner_input = '"$local_normalized"';
else
    runner_input = '"$local_input"';
end

runner_command = [q_runner ' ' q_mcr_root ' ' runner_input ' ' ...
    q_batch_templates ' 0 ' num2str(check_aliasing) ' ' q_defaults_mat];
lines{end + 1} = 'mlsc_record_progress ''pseudoCT|start''';
lines{end + 1} = runner_command;
lines{end + 1} = 'mlsc_record_progress ''pseudoCT|done''';
lines{end + 1} = 'mlsc_record_progress ''verify|start''';
lines{end + 1} = 'if [ ! -s "$TMPDIR/att_map.nii" ]; then';
lines{end + 1} = '    printf ''Node-local att_map.nii is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 73';
lines{end + 1} = 'fi';
lines{end + 1} = 'mlsc_record_progress ''verify|done''';
lines{end + 1} = 'mlsc_record_progress ''copy_back|start''';
lines{end + 1} = 'cp -- "$TMPDIR/att_map.nii" "$shared_temp/att_map.nii"';
lines{end + 1} = 'if [ ! -s "$shared_temp/att_map.nii" ]; then';
lines{end + 1} = '    printf ''Shared att_map.nii copy-back is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 74';
lines{end + 1} = 'fi';
lines{end + 1} = 'copy_optional() {';
lines{end + 1} = '    if [ -f "$1" ]; then';
lines{end + 1} = '        cp -- "$1" "$2"';
lines{end + 1} = '    fi';
lines{end + 1} = '}';
lines{end + 1} = 'copy_optional "$TMPDIR/Pseudo_CT_AC_Version.txt" "$shared_temp/Pseudo_CT_AC_Version.txt"';
lines{end + 1} = 'copy_optional "$TMPDIR/Fusion_MR_Pseudo_CT_validation.tiff" "$shared_temp/Fusion_MR_Pseudo_CT_validation.tiff"';
if needs_normalization
    lines{end + 1} = 'copy_optional "$local_normalized" "$shared_temp/$normalized_name"';
end
lines{end + 1} = 'mlsc_record_progress ''copy_back|done''';
lines{end + 1} = 'printf ''MLSC node-local processing and verified copy-back completed.\n''';

script_text = local_join_lines(lines);
submission_command = '';
if isfield(runtime, 'script_path') && ~isempty(runtime.script_path)
    if ~isfield(runtime, 'account') || isempty(runtime.account)
        error('pseudo_CT:MLSCAccountRequired', ...
            'A runtime Slurm account is required before MLSC submission.');
    end
    submission_command = ['sbatch --parsable --account ' ...
        local_shell_quote(runtime.account)];
    if isfield(runtime, 'job_name') && ~isempty(runtime.job_name)
        submission_command = [submission_command ' --job-name ' ...
            local_shell_quote(runtime.job_name)];
    end
    submission_command = [submission_command ' -- ' ...
        local_shell_quote(runtime.script_path)];
end

artifact = struct();
artifact.schema = 'pseudo-CT.mlsc-slurm-script/v1';
artifact.script = script_text;
artifact.script_text = script_text;
artifact.submission_command = submission_command;
artifact.sbatch_command = submission_command;
artifact.stdout_log_path = stdout_log_path;
artifact.stderr_log_path = stderr_log_path;
artifact.log_paths = struct('stdout', stdout_log_path, ...
    'stderr', stderr_log_path);
artifact.preflight = preflight;
artifact.progress_filename = progress_filename;
artifact.progress_correlation_id = progress_correlation_id;
artifact.progress_records = mlsc_progress('records');
artifact.progress_path = fullfile(shared_temp, artifact.progress_filename);
artifact.progress_format = 'stage|state per line, LF terminated';
artifact.heavy_processing_root = '$TMPDIR';
artifact.shared_input_staging = 'cp shared subject temp to node-local TMPDIR';
artifact.shared_output_staging = 'cp node-local TMPDIR outputs to shared subject temp';
artifact.required_output = 'att_map.nii';
artifact.optional_outputs = {'Pseudo_CT_AC_Version.txt'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; normalized_name};
artifact.secure_transport_required = true;
end

function value = local_subject_value(subject, names)
value = '';
for ii = 1:length(names)
    if isfield(subject, names{ii})
        value = subject.(names{ii});
        return;
    end
end
end

function [progress_filename, progress_correlation_id] = ...
        local_progress_selection(runtime)
%LOCAL_PROGRESS_SELECTION Exact per-submission progress artifact selection.
%   Uses RUNTIME.submission_correlation_id when present; otherwise the
%   legacy fixed name for direct generation only.  The Slurm script writes
%   only the selected file.  R2010b only.
progress_filename = '';
progress_correlation_id = '';
try
    if isstruct(runtime) && numel(runtime) == 1 && ...
            isfield(runtime, 'submission_correlation_id')
        candidate = runtime.submission_correlation_id;
        if ischar(candidate) && size(candidate, 1) == 1 && ...
                ~isempty(candidate)
            progress_filename = mlsc_progress('filename_for', candidate);
            progress_correlation_id = candidate(:)';
            progress_correlation_id = reshape(progress_correlation_id, ...
                1, numel(progress_correlation_id));
            return;
        elseif isempty(candidate)
            % Empty means direct generation without a submission identity.
        else
            error('pseudo_CT:MLSCProgressCorrelation', ...
                'A non-secret MLSC correlation identity is required.');
        end
    end
catch ME
    if strcmp(ME.identifier, 'pseudo_CT:MLSCProgressCorrelation')
        rethrow(ME);
    end
end
if isempty(progress_filename)
    progress_filename = mlsc_progress('filename');
    progress_correlation_id = '';
end
end

function quoted = local_shell_quote(value)
% POSIX shell quoting that remains safe for spaces, quotes, and metacharacters.
single_quote = char(39);
double_quote = char(34);
quoted = single_quote;
for ii = 1:length(value)
    if value(ii) == char(0)
        error('pseudo_CT:MLSCPreflight', ...
            'An MLSC shell value contains a NUL character.');
    elseif value(ii) == single_quote
        quoted = [quoted single_quote double_quote single_quote ...
            double_quote single_quote]; %#ok<AGROW>
    else
        quoted = [quoted value(ii)]; %#ok<AGROW>
    end
end
quoted = [quoted single_quote];
end

function text = local_join_lines(lines)
text = '';
newline_char = sprintf('\n');
for ii = 1:length(lines)
    text = [text lines{ii} newline_char]; %#ok<AGROW>
end
end

function value = local_strip_trailing_separators(value)
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end
