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
%   T004 current branch (T014 authoritative): when CONFIG selects MLSC
%   current, the payload portion only is parameterized. The script stages
%   shared input plus job/resource manifests to node-local $TMPDIR, runs
%   prepare (bundled alias/recenter) BEFORE the unchanged external
%   FreeSurfer tcsh contract, then compute, then verified copy-back. The
%   launcher is invoked as <runner> <pinned MCR_ROOT> <phase>
%   <job_manifest> <resource_manifest> matching the T003 payload CLI.
%   Legacy invocation/ordering is untouched. Resources use CONFIG.mlsc
%   scheduler values (provisional basic/1/1/32G/4h with CPU unchosen for the
%   future profile); OMP/MKL exports derive from SLURM_CPUS_PER_TASK without
%   claiming enforcement and without -singleCompThread forcing. The generated
%   launcher owns the Runtime environment; no global LD_LIBRARY_PATH is
%   constructed here. Single generic assembly path (R005): shared
%   directives/TMPDIR/progress/env/staging/sbatch/metadata via
%   local_generic_* helpers; narrow current payload/manifest/output-contract
%   branches only. Legacy emitted behavior is byte-identical.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 3 || isempty(runtime)
    runtime = struct();
end
preflight = mlsc_preflight(subject, config, runtime);
is_current = false;
try
    is_current = mlsc_current_validate('is_current', config);
catch %#ok<CTCH>
    is_current = false;
end
if is_current
    artifact = local_generate_current(subject, config, runtime, preflight);
    return;
end
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

% Single generic assembly path (R005): shared directives/vars/progress/
% TMPDIR/env/staging/sbatch/metadata via generic helpers; narrow legacy
% payload/output-contract branches below. Current reuses the same helpers.
lines = {};
lines = local_append_generic(lines, local_generic_directives(mlsc, ...
    q_stdout_log_path, q_stderr_log_path));
lines = local_append_generic(lines, local_generic_shared_vars( ...
    q_shared_input, q_shared_temp, q_input_name, q_normalized_name));
[progress_filename, progress_correlation_id] = ...
    local_progress_selection(runtime);
lines = local_append_generic(lines, local_generic_progress_tmpdir( ...
    progress_filename));
lines = local_append_generic(lines, local_generic_env_staging());

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

% Copy all node-local processing files back to the shared directory.
lines{end + 1} = 'find "$TMPDIR" -mindepth 1 -maxdepth 1 -exec cp -a -t "$shared_temp" -- {} +';

lines{end + 1} = 'if [ ! -s "$shared_temp/att_map.nii" ]; then';
lines{end + 1} = '    printf ''Shared att_map.nii copy-back is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 74';
lines{end + 1} = 'fi';

lines{end + 1} = 'mlsc_record_progress ''copy_back|done''';
lines{end + 1} = 'printf ''MLSC node-local processing and verified copy-back completed.\n''';

script_text = local_join_lines(lines);
submission_command = local_generic_sbatch(runtime);

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

function lines = local_generic_directives(mlsc, q_stdout_log_path, q_stderr_log_path)
%LOCAL_GENERIC_DIRECTIVES Single generic Slurm directives path (R005).
%   Shared by legacy and current; no second construction. R2010b only.
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
end

function lines = local_generic_shared_vars(q_shared_input, q_shared_temp, q_input_name, q_normalized_name)
%LOCAL_GENERIC_SHARED_VARS Single generic shared-vars path (R005).
lines = {};
lines{end + 1} = ['shared_input=' q_shared_input];
lines{end + 1} = ['shared_temp=' q_shared_temp];
lines{end + 1} = ['input_name=' q_input_name];
lines{end + 1} = ['normalized_name=' q_normalized_name];
end

function lines = local_generic_progress_tmpdir(progress_filename, include_executor_provenance)
%LOCAL_GENERIC_PROGRESS_TMPDIR Single generic progress/TMPDIR path (R005).
%   Progress file, record helper, node-local TMPDIR guards, shared
%   input/temp checks, and write-probe. R2010b only.
if nargin < 2
    include_executor_provenance = false;
end
lines = {};
lines{end + 1} = ['progress_file="$shared_temp/' progress_filename '"'];
lines{end + 1} = 'mlsc_record_progress() {';
lines{end + 1} = '    (umask 077; printf ''%s\n'' "$1" >> "$progress_file") || true';
lines{end + 1} = '}';
if ~include_executor_provenance
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
end
lines{end + 1} = 'shared_probe="$shared_temp/.mlsc_preflight.$$"';
lines{end + 1} = 'shared_probe_created=0';
lines{end + 1} = 'cleanup_shared_probe() {';
lines{end + 1} = '    if [ "$shared_probe_created" -eq 1 ]; then';
lines{end + 1} = '        rm -f -- "$shared_probe"';
lines{end + 1} = '    fi';
lines{end + 1} = '}';
if include_executor_provenance
    lines{end + 1} = 'mlsc_capture_executor_provenance() {';
    lines{end + 1} = '    local provenance_exit_status="$1"';
    lines{end + 1} = '    local provenance_job_id="${SLURM_JOB_ID:-}"';
    lines{end + 1} = '    local provenance_sidecar_name';
    lines{end + 1} = '    case "$provenance_job_id" in';
    lines{end + 1} = '        ""|*[!0-9]*) provenance_job_id="Not confirmed"; provenance_sidecar_name="mlsc_executor_provenance_unknown.txt" ;;';
    lines{end + 1} = '        *) provenance_sidecar_name="mlsc_executor_provenance_${provenance_job_id}.txt" ;;';
    lines{end + 1} = '    esac';
    lines{end + 1} = '    local provenance_hostname';
    lines{end + 1} = '    local provenance_cpu_model';
    lines{end + 1} = '    local provenance_architecture';
    lines{end + 1} = '    local provenance_mcr_root="${current_mcr_root:-Not confirmed}"';
    lines{end + 1} = '    local provenance_library_dir';
    lines{end + 1} = '    local provenance_library_present';
    lines{end + 1} = '    local provenance_runtime_release="${actual_mcr_release:-Not confirmed}"';
    lines{end + 1} = '    local provenance_shell_outcome';
    lines{end + 1} = '    local provenance_path';
    lines{end + 1} = '    provenance_hostname="$(hostname 2>/dev/null || true)"';
    lines{end + 1} = '    provenance_cpu_model="$(awk -F: ''/^model name[[:space:]]*:/ {sub(/^[[:space:]]*/, "", $2); print $2; exit}'' /proc/cpuinfo 2>/dev/null || true)"';
    lines{end + 1} = '    provenance_architecture="$(uname -m 2>/dev/null || true)"';
    lines{end + 1} = '    if [ -z "$provenance_hostname" ]; then provenance_hostname="Not confirmed"; fi';
    lines{end + 1} = '    if [ -z "$provenance_cpu_model" ]; then provenance_cpu_model="Not confirmed"; fi';
    lines{end + 1} = '    if [ -z "$provenance_architecture" ]; then provenance_architecture="Not confirmed"; fi';
    lines{end + 1} = '    if [ "$provenance_mcr_root" = "Not confirmed" ]; then';
    lines{end + 1} = '        provenance_library_dir="Not confirmed"';
    lines{end + 1} = '        provenance_library_present="Not confirmed"';
    lines{end + 1} = '    else';
    lines{end + 1} = '        provenance_library_dir="${provenance_mcr_root%/}/runtime/glnxa64"';
    lines{end + 1} = '        if [ -d "$provenance_library_dir" ]; then provenance_library_present="yes"; else provenance_library_present="no"; fi';
    lines{end + 1} = '    fi';
    lines{end + 1} = '    case "$provenance_exit_status" in';
    lines{end + 1} = '        ""|*[!0-9]*) provenance_shell_outcome="Not confirmed" ;;';
    lines{end + 1} = '        0) provenance_shell_outcome="completed" ;;';
    lines{end + 1} = '        *) provenance_shell_outcome="failed" ;;';
    lines{end + 1} = '    esac';
    lines{end + 1} = '    if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && [ -w "$TMPDIR" ]; then';
    lines{end + 1} = '        provenance_path="$TMPDIR/$provenance_sidecar_name"';
    lines{end + 1} = '    else';
    lines{end + 1} = '        provenance_path="$shared_temp/$provenance_sidecar_name"';
    lines{end + 1} = '    fi';
    lines{end + 1} = '    {';
    lines{end + 1} = '        printf ''schema=%s\n'' ''pseudo-CT.mlsc-executor-provenance/v1''';
    lines{end + 1} = '        printf ''job_id=%s\n'' "$provenance_job_id"';
    lines{end + 1} = '        printf ''hostname=%s\n'' "$provenance_hostname"';
    lines{end + 1} = '        printf ''cpu_model=%s\n'' "$provenance_cpu_model"';
    lines{end + 1} = '        printf ''architecture=%s\n'' "$provenance_architecture"';
    lines{end + 1} = '        printf ''shell_exit_code=%s\n'' "$provenance_exit_status"';
    lines{end + 1} = '        printf ''shell_terminal_outcome=%s\n'' "$provenance_shell_outcome"';
    lines{end + 1} = '        printf ''selected_mcr_root=%s\n'' "$provenance_mcr_root"';
    lines{end + 1} = '        printf ''runtime_library_dir=%s\n'' "$provenance_library_dir"';
    lines{end + 1} = '        printf ''runtime_library_present=%s\n'' "$provenance_library_present"';
    lines{end + 1} = '        printf ''runtime_release=%s\n'' "$provenance_runtime_release"';
    lines{end + 1} = '        printf ''build_manifest_compiler_release=%s\n'' "$recorded_build_release"';
    lines{end + 1} = '        printf ''build_manifest_mcr_version=%s\n'' "$recorded_build_mcr_version"';
    lines{end + 1} = '        printf ''build_manifest_generation=%s\n'' "$recorded_build_generation"';
    lines{end + 1} = '        printf ''build_manifest_arch=%s\n'' "$recorded_build_arch"';
    lines{end + 1} = '        printf ''build_manifest_mcr_root=%s\n'' "$recorded_build_mcr_root"';
    lines{end + 1} = '        printf ''build_manifest_source_commit=%s\n'' "$recorded_build_source_commit"';
    lines{end + 1} = '        printf ''build_manifest_runner_checksum=%s\n'' "$recorded_build_runner_checksum"';
    lines{end + 1} = '    } > "$provenance_path" 2>/dev/null || return 0';
    lines{end + 1} = '    if [ "$provenance_path" != "$shared_temp/$provenance_sidecar_name" ]; then';
    lines{end + 1} = '        cp -- "$provenance_path" "$shared_temp/$provenance_sidecar_name" >/dev/null 2>&1 || true';
    lines{end + 1} = '    fi';
    lines{end + 1} = '    return 0';
    lines{end + 1} = '}';
    lines{end + 1} = 'trap ''mlsc_capture_executor_provenance "$?" || true; cleanup_shared_probe || true'' EXIT';
else
    lines{end + 1} = 'trap cleanup_shared_probe EXIT';
end
if include_executor_provenance
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
end
lines{end + 1} = 'if ! (umask 077; set -C; : > "$shared_probe"); then';
lines{end + 1} = '    printf ''Shared MLSC subject temp failed its write preflight.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'shared_probe_created=1';
end

function lines = local_generic_env_staging()
%LOCAL_GENERIC_ENV_STAGING Single generic env/staging path (R005).
%   Node-local input/normalized, MCR cache, OMP/MKL derivation (observability
%   only, no enforcement), staging, and stage-in milestone. R2010b only.
lines = {};
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
end

function lines = local_generic_env_pre()
%LOCAL_GENERIC_ENV_PRE Shared env/staging prefix without cd/stage-in (R005).
%   Used by current so manifest staging precedes cd/stage-in in the narrow
%   manifest branch while reusing the single generic env construction.
lines = {};
lines{end + 1} = 'local_input="$TMPDIR/$input_name"';
lines{end + 1} = 'local_normalized="$TMPDIR/$normalized_name"';
lines{end + 1} = 'MCR_CACHE_ROOT="$TMPDIR/mcr_cache"';
lines{end + 1} = 'export MCR_CACHE_ROOT';
lines{end + 1} = ': "${SLURM_CPUS_PER_TASK:?SLURM_CPUS_PER_TASK is required}"';
lines{end + 1} = 'export OMP_NUM_THREADS="$SLURM_CPUS_PER_TASK"';
lines{end + 1} = 'export MKL_NUM_THREADS="$SLURM_CPUS_PER_TASK"';
lines{end + 1} = 'mkdir -p -- "$MCR_CACHE_ROOT"';
lines{end + 1} = 'cp -- "$shared_input" "$local_input"';
end

function command = local_generic_sbatch(runtime)
%LOCAL_GENERIC_SBATCH Single generic sbatch construction (R005).
command = '';
if isfield(runtime, 'script_path') && ~isempty(runtime.script_path)
    if ~isfield(runtime, 'account') || isempty(runtime.account)
        error('pseudo_CT:MLSCAccountRequired', ...
            'A runtime Slurm account is required before MLSC submission.');
    end
    command = ['sbatch --parsable --account ' ...
        local_shell_quote(runtime.account)];
    if isfield(runtime, 'job_name') && ~isempty(runtime.job_name)
        command = [command ' --job-name ' ...
            local_shell_quote(runtime.job_name)];
    end
    command = [command ' -- ' ...
        local_shell_quote(runtime.script_path)];
end
end

function lines = local_append_generic(lines, extra)
%LOCAL_APPEND_GENERIC Append generic helper lines (R005, R2010b only).
if isempty(extra)
    return;
end
for ii = 1:length(extra)
    lines{end + 1} = extra{ii}; %#ok<AGROW>
end
end

function artifact = local_generate_current(subject, config, runtime, preflight)
%LOCAL_GENERATE_CURRENT Current-only Slurm script (T004, T014).
%   Smallest payload-only seam: reuses the generic prologue (TMPDIR,
%   shared checks, progress file, MCR_CACHE_ROOT, OMP/MKL derived from
%   allocation without enforcement) and the unchanged external FreeSurfer
%   tcsh contract. Stages shared input plus job/resource manifests to
%   $TMPDIR, runs prepare BEFORE normalization then compute via the pinned
%   launcher <runner> <MCR_ROOT> <phase> <job> <resources>, verifies the
%   three required outputs plus mandatory evidence (exit nonzero on missing
%   even if launcher exit 0), and copies back before exit. Normalization
%   uses the PREPARE-validated handoff derivation (selected input,
%   normalization need, _normalized basename) resolved at runtime from
%   controlled basenames without sourcing/evaluating the .mat handoff.
%   No SCP, no global LD_LIBRARY_PATH, no catalog/resolver, legacy untouched.
current = config.current;
mlsc = config.mlsc;
shared_input = local_subject_value(subject, {'shared_input'; 'seed_nii'});
shared_temp = local_subject_value(subject, {'shared_temp'; 'temp_dir'});
shared_temp = local_strip_trailing_separators(shared_temp);
check_aliasing = preflight.check_aliasing;
input_name = preflight.input_name;
normalized_name = preflight.normalized_name;
needs_normalization = preflight.needs_normalization;
% PREPARE-validated derivation (mirrors pseudo_CT_current_prepare and
% mlsc_current_payload handoff checks): the corrected variant and its
% _normalized expectation. The runtime shell selects between raw and
% corrected via existence + controlled-basename validation, never by
% sourcing/evaluating the .mat handoff.
corrected_name = local_corrected_variant_name(input_name);
corrected_normalized_name = local_derived_normalized_name(corrected_name);
pinned = mlsc_current_validate('pinned_mcr_root');
runner_path = strtrim(current.runner);
mcr_root = strtrim(current.mcr_root);
build_manifest_path = strtrim(current.build_manifest);
resource_manifest_path = strtrim(current.resource_manifest);
resources = local_load_current_resources(resource_manifest_path);
build = local_load_current_build(build_manifest_path);
recorded_build_release = local_manifest_text(build, 'release');
recorded_build_mcr_version = local_manifest_text(build, 'mcr_version');
recorded_build_generation = local_manifest_text(build, 'generation');
recorded_build_arch = local_manifest_text(build, 'arch');
recorded_build_mcr_root = local_manifest_text(build, 'mcr_root');
recorded_build_source_commit = local_manifest_text(build, 'source_commit');
recorded_build_runner_checksum = local_manifest_text(build, 'runner_checksum');
atlas_dir = strtrim(resources.atlas_dir);
recenter_text = local_effective_yes_no(subject, config, ...
    {'recenter_before_normalization'}, 'Yes');
zero_text = local_effective_yes_no(subject, config, ...
    {'zero_background'}, 'No');
bone_value = local_effective_bone(config);
job_manifest_name = 'mlsc_current_job.mat';
[~, resource_base, resource_ext] = fileparts(resource_manifest_path);
resource_stage_name = [resource_base resource_ext];
if isempty(resource_stage_name)
    resource_stage_name = 'mlsc_current_resources.mat';
end
shared_job_manifest = fullfile(shared_temp, job_manifest_name);
local_write_current_job_manifest(shared_job_manifest, input_name, ...
    atlas_dir, check_aliasing, recenter_text, bone_value, zero_text);
% TOCTOU preflight identities (exact): runner/exe, build/resource
% manifest bytes + mandatory SHA-256, pinned MCR_ROOT release/version/
% update/arch/generation from disk. Embedded below and rechecked before
% PREPARE; any change after preflight fails before any science. If hashing
% is unavailable generation fails closed here (before PREPARE). R2010b only.
expected_runner_bytes = local_file_bytes(runner_path);
expected_runner_sha256 = local_file_sha256_hex(runner_path);
expected_build_bytes = local_file_bytes(build_manifest_path);
expected_build_sha256 = local_file_sha256_hex(build_manifest_path);
expected_resource_bytes = local_file_bytes(resource_manifest_path);
expected_resource_sha256 = local_file_sha256_hex(resource_manifest_path);
expected_job_bytes = local_file_bytes(shared_job_manifest);
if isempty(expected_runner_sha256) || isempty(expected_build_sha256) || ...
        isempty(expected_resource_sha256)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Current identity hashing is unavailable; failing closed before PREPARE.');
end
expected_mcr = mlsc_current_validate('actual_identity', pinned);
q_shared_input = local_shell_quote(shared_input);
q_shared_temp = local_shell_quote(shared_temp);
q_input_name = local_shell_quote(input_name);
q_normalized_name = local_shell_quote(normalized_name);
q_corrected_name = local_shell_quote(corrected_name);
q_corrected_normalized = local_shell_quote(corrected_normalized_name);
q_freesurfer_env = local_shell_quote(mlsc.freesurfer_env);
q_runner = local_shell_quote(runner_path);
q_mcr_root = local_shell_quote(mcr_root);
q_shared_job = local_shell_quote(shared_job_manifest);
q_shared_resources = local_shell_quote(resource_manifest_path);
q_shared_build = local_shell_quote(build_manifest_path);
stdout_log_path = fullfile(shared_temp, 'pseudoCT_mlsc_%j.out');
stderr_log_path = fullfile(shared_temp, 'pseudoCT_mlsc_%j.err');
q_stdout_log_path = local_shell_quote(stdout_log_path);
q_stderr_log_path = local_shell_quote(stderr_log_path);
% Single generic assembly path (R005): shared directives/vars/progress/
% TMPDIR/env/staging/sbatch via generic helpers; narrow current
% payload/manifest/output-contract branches below. Legacy uses the same
% helpers above.
lines = {};
lines = local_append_generic(lines, local_generic_directives(mlsc, ...
    q_stdout_log_path, q_stderr_log_path));
lines = local_append_generic(lines, local_generic_shared_vars( ...
    q_shared_input, q_shared_temp, q_input_name, q_normalized_name));
lines{end + 1} = ['shared_job_manifest=' q_shared_job];
lines{end + 1} = ['shared_resource_manifest=' q_shared_resources];
lines{end + 1} = ['shared_build_manifest=' q_shared_build];
lines{end + 1} = ['current_runner=' q_runner];
lines{end + 1} = ['current_mcr_root=' q_mcr_root];
lines{end + 1} = 'actual_mcr_release=""';
lines{end + 1} = ['recorded_build_release=' local_shell_quote(recorded_build_release)];
lines{end + 1} = ['recorded_build_mcr_version=' local_shell_quote(recorded_build_mcr_version)];
lines{end + 1} = ['recorded_build_generation=' local_shell_quote(recorded_build_generation)];
lines{end + 1} = ['recorded_build_arch=' local_shell_quote(recorded_build_arch)];
lines{end + 1} = ['recorded_build_mcr_root=' local_shell_quote(recorded_build_mcr_root)];
lines{end + 1} = ['recorded_build_source_commit=' local_shell_quote(recorded_build_source_commit)];
lines{end + 1} = ['recorded_build_runner_checksum=' local_shell_quote(recorded_build_runner_checksum)];
[progress_filename, progress_correlation_id] = ...
    local_progress_selection(runtime);
lines = local_append_generic(lines, local_generic_progress_tmpdir( ...
    progress_filename, true));
% Startup TOCTOU recheck avoids time-of-check/time-of-use drift:
% pre-submission validated the pinned artifact, but shared paths could
% have changed before sbatch startup. Before any current science (before
% PREPARE), revalidates staged/current runner/exe identity, build/resource
% manifest identity, pinned MCR_ROOT identity/metadata with the SAME
% semantic rules as mlsc_current_validate (exact release, full
% version/build, numeric update, arch/platform, numeric mcrversion via
% generation; no substring matching so Update 2 vs Update 20 cannot
% confuse), native state (via resource-manifest identity), and artifact/
% resource fingerprints/checksums from preflight (mandatory SHA-256).
% Existence/nonempty alone is insufficient: byte sizes and SHA-256 content
% hashes must match preflight, and hashing-unavailable or missing utility
% fails closed before PREPARE. A changed runner/manifest/metadata after
% preflight fails here, before PREPARE is ever entered. The
% generated launcher owns the Runtime environment; no global
% LD_LIBRARY_PATH is manufactured here (only env -u isolation for the
% FreeSurfer step). Library-priority: only truthful evidence is checked
% now (MCR_ROOT plus library structure/metadata below); Gate-A dynamic
% loading proof is explicitly Gate-A-required state and is NOT faked here.
q_pinned_mcr = local_shell_quote(pinned);
lines{end + 1} = ['pinned_mcr_root=' q_pinned_mcr];
lines{end + 1} = ['expected_runner_bytes=' num2str(expected_runner_bytes, '%.0f')];
lines{end + 1} = ['expected_runner_sha256=' local_shell_quote(expected_runner_sha256)];
lines{end + 1} = ['expected_build_bytes=' num2str(expected_build_bytes, '%.0f')];
lines{end + 1} = ['expected_build_sha256=' local_shell_quote(expected_build_sha256)];
lines{end + 1} = ['expected_resource_bytes=' num2str(expected_resource_bytes, '%.0f')];
lines{end + 1} = ['expected_resource_sha256=' local_shell_quote(expected_resource_sha256)];
lines{end + 1} = ['expected_mcr_release=' local_shell_quote(expected_mcr.release)];
lines{end + 1} = ['expected_mcr_version=' local_shell_quote(expected_mcr.version)];
lines{end + 1} = ['expected_mcr_update=' num2str(expected_mcr.update, '%.0f')];
lines{end + 1} = ['expected_mcr_arch=' local_shell_quote(expected_mcr.arch)];
lines{end + 1} = ['expected_mcr_generation=' local_shell_quote(expected_mcr.generation)];
lines{end + 1} = 'if [ "$current_mcr_root" != "$pinned_mcr_root" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT does not match the pinned contract.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -f "$current_runner" ]; then';
lines{end + 1} = '    printf ''Current runner is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$current_runner" ]; then';
lines{end + 1} = '    printf ''Current runner is empty.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'runner_bytes=$(wc -c < "$current_runner" | tr -d '' '')';
lines{end + 1} = 'if [ "$runner_bytes" != "$expected_runner_bytes" ]; then';
lines{end + 1} = '    printf ''Current runner changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = '# B4B immutable identity: SHA-256 MANDATORY. Missing expected hash';
lines{end + 1} = '# or missing hash utility fails closed before PREPARE (no';
lines{end + 1} = '# filesize-only fallback, so same-size mutation is detected).';
lines{end + 1} = 'if [ -z "$expected_runner_sha256" ]; then';
lines{end + 1} = '    printf ''Current runner hash is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if ! command -v sha256sum >/dev/null 2>&1; then';
lines{end + 1} = '    printf ''Current hash utility is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'runner_sha=$(sha256sum "$current_runner" | cut -d '' '' -f1)';
lines{end + 1} = 'if [ "$runner_sha" != "$expected_runner_sha256" ]; then';
lines{end + 1} = '    printf ''Current runner content changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -d "$current_mcr_root" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -d "$current_mcr_root/runtime/glnxa64" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT structure is malformed.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ -f "$current_mcr_root/VersionInfo.xml" ]; then';
lines{end + 1} = '# B4A exact MCR identity (same rules as mlsc_current_validate):';
lines{end + 1} = '# extract ACTUAL fields from VersionInfo.xml, then exact compare.';
lines{end + 1} = '# No substring matching: Update 2 vs Update 20 cannot confuse';
lines{end + 1} = '# because update is compared as an exact integer and release /';
lines{end + 1} = '# version / arch / generation with exact string equality.';
lines{end + 1} = 'actual_mcr_release=$(sed -n ''s/.*<[Rr][Ee][Ll][Ee][Aa][Ss][Ee]>[[:space:]]*\([^<]*\)[[:space:]]*<\/[Rr][Ee][Ll][Ee][Aa][Ss][Ee]>.*/\1/p'' "$current_mcr_root/VersionInfo.xml" | head -n 1 | tr -d '' \t\r\n'' || true)';
lines{end + 1} = 'if [ -z "$actual_mcr_release" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT release identity is unknown.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ "$actual_mcr_release" != "$expected_mcr_release" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT release changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'actual_mcr_version=$(sed -n ''s/.*<[Vv][Ee][Rr][Ss][Ii][Oo][Nn]>[[:space:]]*\([^<]*\)[[:space:]]*<\/[Vv][Ee][Rr][Ss][Ii][Oo][Nn]>.*/\1/p'' "$current_mcr_root/VersionInfo.xml" | head -n 1 | tr -d '' \t\r\n'' || true)';
lines{end + 1} = 'if [ -z "$actual_mcr_version" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT version identity is unknown.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ "$actual_mcr_version" != "$expected_mcr_version" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT version changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = '# Numeric mcrversion via generation (major.minor from version).';
lines{end + 1} = 'actual_mcr_generation=$(printf ''%s'' "$actual_mcr_version" | cut -d ''.'' -f1,2 || true)';
lines{end + 1} = 'if [ -z "$actual_mcr_generation" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT generation identity is unknown.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ "$actual_mcr_generation" != "$expected_mcr_generation" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT numeric runtime version changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = '# Numeric update: bare integer in <update> tags, else number after';
lines{end + 1} = '# Update text, else Update N anywhere (mirrors mlsc_current_validate).';
lines{end + 1} = 'actual_update_raw=$(sed -n ''s/.*<[Uu][Pp][Dd][Aa][Tt][Ee][^>]*>[[:space:]]*\([^<]*\)[[:space:]]*<\/[Uu][Pp][Dd][Aa][Tt][Ee][^>]*>.*/\1/p'' "$current_mcr_root/VersionInfo.xml" | head -n 1 || true)';
lines{end + 1} = 'actual_mcr_update=""';
lines{end + 1} = 'trimmed_update_raw=$(printf ''%s'' "$actual_update_raw" | tr -d '' \t\r\n'' || true)';
lines{end + 1} = 'case "$trimmed_update_raw" in';
lines{end + 1} = '    "")';
lines{end + 1} = '        ;;';
lines{end + 1} = '    *[!0-9]*)';
lines{end + 1} = '        update_num=$(printf ''%s'' "$actual_update_raw" | grep -o -i -E ''Update[^0-9]*[0-9]+'' | head -n 1 | grep -o -E ''[0-9]+'' | head -n 1 || true)';
lines{end + 1} = '        actual_mcr_update="$update_num"';
lines{end + 1} = '        ;;';
lines{end + 1} = '    *)';
lines{end + 1} = '        actual_mcr_update="$trimmed_update_raw"';
lines{end + 1} = '        ;;';
lines{end + 1} = 'esac';
lines{end + 1} = 'if [ -z "$actual_mcr_update" ]; then';
lines{end + 1} = '    fallback_update=$(grep -o -i -E ''Update[^0-9]*[0-9]+'' "$current_mcr_root/VersionInfo.xml" | head -n 1 | grep -o -E ''[0-9]+'' | head -n 1 || true)';
lines{end + 1} = '    actual_mcr_update="$fallback_update"';
lines{end + 1} = 'fi';
lines{end + 1} = 'case "$actual_mcr_update" in';
lines{end + 1} = '    "")';
lines{end + 1} = '        printf ''Current MCR_ROOT update identity is unknown.\n'' >&2';
lines{end + 1} = '        exit 72';
lines{end + 1} = '        ;;';
lines{end + 1} = '    *[!0-9]*)';
lines{end + 1} = '        printf ''Current MCR_ROOT update identity is malformed.\n'' >&2';
lines{end + 1} = '        exit 72';
lines{end + 1} = '        ;;';
lines{end + 1} = 'esac';
lines{end + 1} = '# Exact numeric compare (Update 2 vs Update 20 cannot confuse).';
lines{end + 1} = 'if [ "$actual_mcr_update" -ne "$expected_mcr_update" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT update changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = '# Arch/platform: explicit tag when present must exactly match;';
lines{end + 1} = '# absent tag falls back to the runtime/glnxa64 structure guard above.';
lines{end + 1} = 'actual_mcr_arch=$(sed -n ''s/.*<[Aa][Rr][Cc][Hh]>[[:space:]]*\([^<]*\)[[:space:]]*<\/[Aa][Rr][Cc][Hh]>.*/\1/p'' "$current_mcr_root/VersionInfo.xml" | head -n 1 | tr -d '' \t\r\n'' || true)';
lines{end + 1} = 'if [ -z "$actual_mcr_arch" ]; then';
lines{end + 1} = '    actual_mcr_arch=$(sed -n ''s/.*<[Pp][Ll][Aa][Tt][Ff][Oo][Rr][Mm]>[[:space:]]*\([^<]*\)[[:space:]]*<\/[Pp][Ll][Aa][Tt][Ff][Oo][Rr][Mm]>.*/\1/p'' "$current_mcr_root/VersionInfo.xml" | head -n 1 | tr -d '' \t\r\n'' || true)';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ -z "$actual_mcr_arch" ]; then';
lines{end + 1} = '    actual_mcr_arch=$(sed -n ''s/.*<[Aa][Rr][Cc][Hh][Ii][Tt][Ee][Cc][Tt][Uu][Rr][Ee]>[[:space:]]*\([^<]*\)[[:space:]]*<\/[Aa][Rr][Cc][Hh][Ii][Tt][Ee][Cc][Tt][Uu][Rr][Ee]>.*/\1/p'' "$current_mcr_root/VersionInfo.xml" | head -n 1 | tr -d '' \t\r\n'' || true)';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ -z "$actual_mcr_arch" ]; then';
lines{end + 1} = '    actual_mcr_arch="glnxa64"';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ "$actual_mcr_arch" != "$expected_mcr_arch" ]; then';
lines{end + 1} = '    printf ''Current MCR_ROOT architecture changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'else';
lines{end + 1} = '    # MCR 7.14 has no VersionInfo.xml; the exact pinned root plus';
lines{end + 1} = '    # runtime library path is its fail-closed identity check.';
lines{end + 1} = '    if [ "$expected_mcr_generation" != "7.14" ] || [ ! -s "$current_mcr_root/runtime/glnxa64/libmwmclmcrrt.so" ]; then';
lines{end + 1} = '        printf ''Pinned MCR 7.14 runtime identity is invalid.\n'' >&2';
lines{end + 1} = '        exit 72';
lines{end + 1} = '    fi';
lines{end + 1} = 'fi';
lines{end + 1} = '# Gate-A dynamic loading is Gate-A-required state (not proven here);';
lines{end + 1} = '# only MCR_ROOT plus library structure/metadata is verified now.';
lines{end + 1} = 'if [ ! -s "$shared_build_manifest" ]; then';
lines{end + 1} = '    printf ''Current build manifest is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'build_bytes=$(wc -c < "$shared_build_manifest" | tr -d '' '')';
lines{end + 1} = 'if [ "$build_bytes" != "$expected_build_bytes" ]; then';
lines{end + 1} = '    printf ''Current build manifest changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ -z "$expected_build_sha256" ]; then';
lines{end + 1} = '    printf ''Current build manifest hash is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if ! command -v sha256sum >/dev/null 2>&1; then';
lines{end + 1} = '    printf ''Current hash utility is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'build_sha=$(sha256sum "$shared_build_manifest" | cut -d '' '' -f1)';
lines{end + 1} = 'if [ "$build_sha" != "$expected_build_sha256" ]; then';
lines{end + 1} = '    printf ''Current build manifest content changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$shared_resource_manifest" ]; then';
lines{end + 1} = '    printf ''Current resource manifest is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'resource_bytes=$(wc -c < "$shared_resource_manifest" | tr -d '' '')';
lines{end + 1} = 'if [ "$resource_bytes" != "$expected_resource_bytes" ]; then';
lines{end + 1} = '    printf ''Current resource manifest changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ -z "$expected_resource_sha256" ]; then';
lines{end + 1} = '    printf ''Current resource manifest hash is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if ! command -v sha256sum >/dev/null 2>&1; then';
lines{end + 1} = '    printf ''Current hash utility is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'resource_sha=$(sha256sum "$shared_resource_manifest" | cut -d '' '' -f1)';
lines{end + 1} = 'if [ "$resource_sha" != "$expected_resource_sha256" ]; then';
lines{end + 1} = '    printf ''Current resource manifest content changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$shared_job_manifest" ]; then';
lines{end + 1} = '    printf ''Current job manifest is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
% Shared env/staging via the single generic path; narrow current manifest
% staging follows as the payload/manifest branch before cd/stage-in.
lines = local_append_generic(lines, local_generic_env_pre());
lines{end + 1} = ['local_job_manifest="$TMPDIR/' job_manifest_name '"'];
lines{end + 1} = ['local_resource_manifest="$TMPDIR/' resource_stage_name '"'];
lines{end + 1} = 'cp -- "$shared_job_manifest" "$local_job_manifest"';
lines{end + 1} = 'cp -- "$shared_resource_manifest" "$local_resource_manifest"';
lines{end + 1} = 'cd "$TMPDIR"';
lines{end + 1} = 'mlsc_record_progress ''stage_in|done''';
lines{end + 1} = 'if [ ! -s "$local_job_manifest" ]; then';
lines{end + 1} = '    printf ''Staged job manifest is missing.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$local_resource_manifest" ]; then';
lines{end + 1} = '    printf ''Staged resource manifest is missing.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'staged_resource_bytes=$(wc -c < "$local_resource_manifest" | tr -d '' '')';
lines{end + 1} = 'if [ "$staged_resource_bytes" != "$expected_resource_bytes" ]; then';
lines{end + 1} = '    printf ''Staged resource manifest changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ -z "$expected_resource_sha256" ]; then';
lines{end + 1} = '    printf ''Staged resource manifest hash is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'if ! command -v sha256sum >/dev/null 2>&1; then';
lines{end + 1} = '    printf ''Current hash utility is unavailable.\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
lines{end + 1} = 'staged_resource_sha=$(sha256sum "$local_resource_manifest" | cut -d '' '' -f1)';
lines{end + 1} = 'if [ "$staged_resource_sha" != "$expected_resource_sha256" ]; then';
lines{end + 1} = '    printf ''Staged resource content changed after preflight (TOCTOU).\n'' >&2';
lines{end + 1} = '    exit 72';
lines{end + 1} = 'fi';
% Preserve prepare -> alias/recenter -> external FreeSurfer normalization
% -> compute. Preparation runs bundled code BEFORE the unchanged MLSC
% shell contract (env -u LD_LIBRARY_PATH ... tcsh -f -c with source
% /usr/local/freesurfer/nmr-stable53-env); normalization is never moved
% into the payload and the launcher never runs inside tcsh. The generated
% launcher owns the Runtime environment; no global LD_LIBRARY_PATH is set.
% Normalization consumes the PREPARE-validated handoff derivation
% (selected input, normalization need, _normalized basename from
% pseudo_CT_current_prepare/mlsc_current_payload handoff checks) resolved
% here from controlled basenames without sourcing or evaluating the .mat
% handoff: when PREPARE produced <base>_corrected.nii, the corrected file
% normalizes to <base>_corrected_normalized.nii consumed by COMPUTE.
lines{end + 1} = 'mlsc_record_progress ''pseudoCT|start''';
lines{end + 1} = '"$current_runner" "$current_mcr_root" prepare "$local_job_manifest" "$local_resource_manifest"';
lines{end + 1} = 'mlsc_record_progress ''preparation|done''';
lines{end + 1} = 'mlsc_record_progress ''alias_recenter|done''';
lines{end + 1} = ['prepare_corrected=' q_corrected_name];
lines{end + 1} = ['prepare_corrected_normalized=' q_corrected_normalized];
lines{end + 1} = 'prepare_selected="$input_name"';
lines{end + 1} = 'prepare_expected="$normalized_name"';
lines{end + 1} = 'if [ -f "$TMPDIR/$prepare_corrected" ]; then';
lines{end + 1} = '    prepare_selected="$prepare_corrected"';
lines{end + 1} = '    prepare_expected="$prepare_corrected_normalized"';
lines{end + 1} = 'fi';
lines{end + 1} = 'case "$prepare_selected" in';
lines{end + 1} = '    *..*|*/*)';
lines{end + 1} = '        printf ''PREPARE-selected input is not a controlled basename.\n'' >&2';
lines{end + 1} = '        exit 72';
lines{end + 1} = '        ;;';
lines{end + 1} = '    *.nii)';
lines{end + 1} = '        ;;';
lines{end + 1} = '    *)';
lines{end + 1} = '        printf ''PREPARE-selected input is not a controlled basename.\n'' >&2';
lines{end + 1} = '        exit 72';
lines{end + 1} = '        ;;';
lines{end + 1} = 'esac';
lines{end + 1} = 'case "$prepare_expected" in';
lines{end + 1} = '    *..*|*/*)';
lines{end + 1} = '        printf ''PREPARE-expected output is not a controlled basename.\n'' >&2';
lines{end + 1} = '        exit 72';
lines{end + 1} = '        ;;';
lines{end + 1} = '    *_normalized.nii)';
lines{end + 1} = '        ;;';
lines{end + 1} = '    *)';
lines{end + 1} = '        printf ''PREPARE-expected output is not a controlled basename.\n'' >&2';
lines{end + 1} = '        exit 72';
lines{end + 1} = '        ;;';
lines{end + 1} = 'esac';
if needs_normalization
    tcsh_program = 'source "$MLSC_FREESURFER_ENV"; mri_normalize "$TMPDIR/$MLSC_INPUT_NAME" "$TMPDIR/$MLSC_NORMALIZED_NAME"';
    lines{end + 1} = 'case "$prepare_selected" in';
    lines{end + 1} = '    *_normalized.nii)';
    lines{end + 1} = '        normalize_needed=0';
    lines{end + 1} = '        ;;';
    lines{end + 1} = '    *)';
    lines{end + 1} = '        normalize_needed=1';
    lines{end + 1} = '        ;;';
    lines{end + 1} = 'esac';
    lines{end + 1} = 'if [ "$normalize_needed" -eq 1 ]; then';
    lines{end + 1} = '    mlsc_record_progress ''normalize|start''';
    lines{end + 1} = ['    env -u LD_LIBRARY_PATH MLSC_FREESURFER_ENV=' q_freesurfer_env ' "MLSC_INPUT_NAME=$prepare_selected" "MLSC_NORMALIZED_NAME=$prepare_expected" tcsh -f -c ''' tcsh_program ''''];
    lines{end + 1} = '    mlsc_record_progress ''normalize|done''';
    lines{end + 1} = 'fi';
    lines{end + 1} = 'if [ "$normalize_needed" -eq 1 ] && [ ! -s "$TMPDIR/$prepare_expected" ]; then';
    lines{end + 1} = '    printf ''Node-local normalized output is missing or empty.\n'' >&2';
    lines{end + 1} = '    exit 73';
    lines{end + 1} = 'fi';
end
lines{end + 1} = '"$current_runner" "$current_mcr_root" compute "$local_job_manifest" "$local_resource_manifest"';
lines{end + 1} = 'mlsc_record_progress ''alignment_mask|done''';
lines{end + 1} = 'mlsc_record_progress ''segmentation|done''';
lines{end + 1} = 'mlsc_record_progress ''bone|done''';
lines{end + 1} = 'mlsc_record_progress ''dartel_warp_reslice|done''';
lines{end + 1} = 'mlsc_record_progress ''pseudoCT|done''';
lines{end + 1} = 'mlsc_record_progress ''attenuation_qc|done''';
lines{end + 1} = 'mlsc_record_progress ''verify|start''';
lines{end + 1} = 'if [ ! -s "$TMPDIR/att_map.nii" ]; then';
lines{end + 1} = '    printf ''Node-local att_map.nii is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 73';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$TMPDIR/Fusion_MR_Pseudo_CT_validation.tiff" ]; then';
lines{end + 1} = '    printf ''Node-local validation output is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 73';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$TMPDIR/Pseudo_CT_AC_Version.txt" ]; then';
lines{end + 1} = '    printf ''Node-local version output is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 73';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$TMPDIR/mlsc_current_handoff.mat" ]; then';
lines{end + 1} = '    printf ''Node-local handoff is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 73';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$TMPDIR/mlsc_current_prepare_evidence.txt" ]; then';
lines{end + 1} = '    printf ''Node-local prepare evidence is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 73';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$TMPDIR/mlsc_current_output_verification.txt" ]; then';
lines{end + 1} = '    printf ''Node-local output verification is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 73';
lines{end + 1} = 'fi';
lines{end + 1} = 'mlsc_record_progress ''verify|done''';
lines{end + 1} = 'mlsc_record_progress ''copy_back|start''';
% Copy all node-local processing files back to the shared directory.
lines{end + 1} = 'find "$TMPDIR" -mindepth 1 -maxdepth 1 -exec cp -a -t "$shared_temp" -- {} +';
lines{end + 1} = 'if [ ! -s "$shared_temp/att_map.nii" ]; then';
lines{end + 1} = '    printf ''Shared att_map.nii copy-back is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 74';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$shared_temp/Fusion_MR_Pseudo_CT_validation.tiff" ]; then';
lines{end + 1} = '    printf ''Shared validation copy-back is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 74';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$shared_temp/Pseudo_CT_AC_Version.txt" ]; then';
lines{end + 1} = '    printf ''Shared version copy-back is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 74';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$shared_temp/mlsc_current_handoff.mat" ]; then';
lines{end + 1} = '    printf ''Shared handoff copy-back is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 74';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$shared_temp/mlsc_current_prepare_evidence.txt" ]; then';
lines{end + 1} = '    printf ''Shared prepare evidence copy-back is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 74';
lines{end + 1} = 'fi';
lines{end + 1} = 'if [ ! -s "$shared_temp/mlsc_current_output_verification.txt" ]; then';
lines{end + 1} = '    printf ''Shared output verification copy-back is missing or empty.\n'' >&2';
lines{end + 1} = '    exit 74';
lines{end + 1} = 'fi';
lines{end + 1} = 'mlsc_record_progress ''copy_back|done''';
lines{end + 1} = 'printf ''MLSC node-local processing and verified copy-back completed.\n''';
script_text = local_join_lines(lines);
submission_command = local_generic_sbatch(runtime);
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
artifact.required_outputs = {'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
artifact.required_evidence = {'mlsc_current_handoff.mat'; ...
    'mlsc_current_prepare_evidence.txt'; ...
    'mlsc_current_output_verification.txt'};
artifact.optional_outputs = {normalized_name};
artifact.secure_transport_required = true;
artifact.is_current = true;
artifact.current_runner = runner_path;
artifact.current_mcr_root = mcr_root;
artifact.current_build_manifest = build_manifest_path;
artifact.current_resource_manifest = resource_manifest_path;
artifact.current_job_manifest = shared_job_manifest;
artifact.network_payload_staging = false;
end

function resources = local_load_current_resources(resource_manifest_path)
loaded = load(resource_manifest_path);
if ~isfield(loaded, 'resources')
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Resource manifest is missing variable resources.');
end
resources = loaded.resources;
if ~isstruct(resources) || numel(resources) ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Resource manifest must be one scalar struct.');
end
end

function build = local_load_current_build(build_manifest_path)
loaded = load(build_manifest_path);
if ~isfield(loaded, 'build') || ~isstruct(loaded.build) || ...
        numel(loaded.build) ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest must contain one scalar struct build.');
end
build = loaded.build;
end

function text = local_manifest_text(build, field_name)
%LOCAL_MANIFEST_TEXT Bounded scalar metadata copied from the build manifest.
text = 'Not confirmed';
try
    if ~isstruct(build) || numel(build) ~= 1 || ...
            ~isfield(build, field_name)
        return;
    end
    value = build.(field_name);
    if ischar(value) && size(value, 1) == 1 && ~isempty(strtrim(value)) && ...
            ~any(value == char(0)) && ...
            isempty(regexp(value, '[\r\n]', 'once'))
        text = strtrim(value);
    elseif strcmp(field_name, 'mcr_version') && isnumeric(value) && ...
            numel(value) == 2 && all(isfinite(value(:))) && ...
            all(value(:) == floor(value(:)))
        text = sprintf('%d.%d', value(1), value(2));
    end
catch %#ok<CTCH>
    text = 'Not confirmed';
end
end

function text = local_effective_yes_no(subject, config, names, fallback)
text = fallback;
for ii = 1:length(names)
    if isfield(subject, names{ii})
        text = local_to_yes_no(subject.(names{ii}), fallback);
        return;
    end
end
if isfield(config, names{1})
    try
        text = local_to_yes_no(config.(names{1}), fallback);
    catch %#ok<CTCH>
    end
end
end

function text = local_to_yes_no(value, fallback)
if ischar(value) && size(value, 1) == 1
    trimmed = strtrim(value);
    if strcmp(trimmed, 'Yes') || strcmp(trimmed, 'No')
        text = trimmed;
        return;
    end
end
if (islogical(value) || isnumeric(value)) && isscalar(value) && ...
        isfinite(double(value))
    if double(value) == 1
        text = 'Yes';
        return;
    end
    if double(value) == 0
        text = 'No';
        return;
    end
end
text = fallback;
end

function value = local_effective_bone(config)
value = false;
try
    if isfield(config, 'bone_enabled')
        candidate = config.bone_enabled;
        if islogical(candidate) && isscalar(candidate)
            value = candidate;
            return;
        end
        if isnumeric(candidate) && isscalar(candidate) && ...
                isfinite(candidate) && ismember(double(candidate), [0 1])
            value = logical(candidate);
            return;
        end
    end
catch %#ok<CTCH>
end
end

function local_write_current_job_manifest(job_path, input_name, atlas_dir, ...
    check_aliasing, recenter_text, bone_value, zero_text)
job = struct();
job.schema = 'pseudo-CT.mlsc-current-job/v1';
job.manifest_version = 1;
job.input_mprage = input_name;
job.work_dir = '.';
job.atlas_dir = atlas_dir;
job.check_aliasing = double(check_aliasing);
job.recenter_before_normalization = recenter_text;
job.bone_enabled = logical(bone_value);
job.zero_background = zero_text;
save(job_path, 'job');
end

function name = local_corrected_variant_name(input_name)
%LOCAL_CORRECTED_VARIANT_NAME PREPARE-corrected basename derivation.
%   Mirrors pseudo_CT_current_prepare output_path and
%   mlsc_current_payload local_corrected_variant: <base>_corrected<ext>.
%   R2010b only.
name = input_name;
try
    if ~ischar(input_name) || size(input_name, 1) ~= 1 || ...
            isempty(strtrim(input_name))
        return;
    end
    trimmed = strtrim(input_name);
    [path_in, base_in, ext_in] = fileparts(trimmed);
    if isempty(base_in)
        return;
    end
    if isempty(ext_in)
        ext_in = '.nii';
    end
    name = fullfile(path_in, [base_in '_corrected' ext_in]);
    % fileparts/fullfile may return row; force single-row char.
    if ~ischar(name) || size(name, 1) ~= 1
        name = input_name;
    end
catch %#ok<CTCH>
    name = input_name;
end
end

function expected = local_derived_normalized_name(selected)
%LOCAL_DERIVED_NORMALIZED_NAME _normalized expectation derivation.
%   Mirrors pseudo_CT_current_prepare local_expected_normalized and
%   mlsc_current_payload local_derived_normalized: <base>_normalized<ext>.
%   R2010b only.
expected = '';
try
    if ~ischar(selected) || size(selected, 1) ~= 1 || ...
            isempty(strtrim(selected))
        return;
    end
    trimmed = strtrim(selected);
    [pathn, namen, extn] = fileparts(trimmed);
    if length(extn) >= 2 && strcmp(extn(end-1:end), ',1')
        extn = extn(1:end-2);
    end
    if isempty(extn)
        extn = '.nii';
    end
    expected = fullfile(pathn, [namen '_normalized' extn]);
catch %#ok<CTCH>
    expected = '';
end
end

function bytes = local_file_bytes(path_text)
%LOCAL_FILE_BYTES Exact byte size for TOCTOU identity (R2010b only).
bytes = 0;
try
    if ~ischar(path_text) || size(path_text, 1) ~= 1 || ...
            isempty(strtrim(path_text))
        return;
    end
    info = dir(strtrim(path_text));
    if ~isempty(info)
        bytes = double(info(1).bytes);
    end
catch %#ok<CTCH>
    bytes = 0;
end
end

function hex = local_file_sha256_hex(path_text)
%LOCAL_FILE_SHA256_HEX Exact content hash for TOCTOU identity (B4B).
%   Java SHA-256 when available, else approved sha256sum. No FNV fallback:
%   when hashing is unavailable the result is '' and generation/startup
%   fail closed. R2010b only.
hex = '';
try
    if ~ischar(path_text) || size(path_text, 1) ~= 1 || ...
            isempty(strtrim(path_text))
        return;
    end
    fid = fopen(strtrim(path_text), 'r');
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
        quoted = local_shell_quote(strtrim(path_text));
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
