% Date: May/28/2026;
% Standalone Launchpad backend that mirrors the old compiled pseudo-CT path.

function [ssh2_conn, jobname, rand_fold, ss_tot] = batch_pseudo_CT_launchpad(P, ssh_log, varargin)

if isempty(varargin) || ~isstruct(varargin{end})
    error('pseudo_CT:ProfileRequired', ...
        'batch_pseudo_CT_launchpad requires the selected profile config.');
end
config = varargin{end};
varargin = varargin(1:end-1);

clean_folder = 1;
keep_tmp = 0;
check_aliasing = config.aliasing_default;
output_log_files = {};

if length(P) == 0
    P = spm_select(Inf, 'any', 'Choose the subjects to run Pseudo-CT on cluster!');
end
if ~iscell(ssh_log) || length(ssh_log) ~= 3
    [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
        'WindowName', 'Enter your Martinos Login and Password to connect to Launchpad and use FreeSurfer!');
    HOSTNAME = config.launchpad.host;
    ssh_log = {USERNAME, PASSWORD, HOSTNAME};
    clear USERNAME PASSWORD HOSTNAME
end

fix_args = 2;
num_extra_args = length(varargin);
if num_extra_args > 0 && rem(num_extra_args, 2) == 0
    for ii=1:2:num_extra_args
        switch varargin{ii}
            case 'clean_folder'
                clean_folder = varargin{ii+1};
            case 'keep_tmp'
                keep_tmp = varargin{ii+1};
            case 'check_aliasing'
                check_aliasing = varargin{ii+1};
            case 'output_contexts'
                output_log_files = varargin{ii+1};
            otherwise
                % Legacy output: disp('Unkown parameter!!');
                pseudo_CT_output('ERROR', struct('log_files', {output_log_files}), ...
                    'Unknown Launchpad parameter: %s', varargin{ii});
                return
        end
    end
elseif rem(num_extra_args, 2) ~= 0
    % Legacy output: disp(sprintf('The total number of input variables must be: (%d fix + multiples of 2 for extra parameters)!!!', fix_args));
    pseudo_CT_output('ERROR', struct('log_files', {output_log_files}), ...
        'Launchpad options must be supplied as name/value pairs.');
    return
end

FS = 1;
% Profile queue selection takes priority (e.g. 'p60' for faster scheduling).
% If empty, fall back to
% the hardcoded heuristic (-q max100 for >100 subjects, default otherwise).
queue_override = config.launchpad.queue;
if ~isempty(queue_override)
    queue_com = ['-q ', queue_override];
elseif size(P, 1) > 100
    queue_com = '-q max100';
else
    queue_com = '';
end

att_map_filename = 'att_map.nii';
evidence = launchpad_evidence('init', struct('profile', 'launchpad', ...
    'subject_count', size(P, 1)));

ssh2_conn = ssh2_config(ssh_log{3}, ssh_log{1}, ssh_log{2});
host_folder = config.launchpad.scratch;
if ~strcmp(host_folder(end), '/')
    host_folder = [host_folder, '/'];
end
lc_path_parent = strcat(host_folder, ssh2_conn.username, '/');
ssh2_conn = ssh2_command(ssh2_conn, sprintf('mkdir %s', lc_path_parent));

launchpad_batch_templates = config.launchpad.batch_templates;
launchpad_defaults_mat = config.launchpad.defaults_mat;
launchpad_runner = config.launchpad.runner;
launchpad_mcr_root = config.launchpad.mcr_root;

for jj=1:size(P, 1)
    % Legacy output: disp(sprintf('Working on subject %d of %d:\n%s\n', jj, size(P, 1), deblank(P(jj, :))));
    context = local_context(output_log_files, jj, size(P, 1), 2);
    stage_started = tic;
    pseudo_CT_output('INFO', context, 'Uploading input and submitting Launchpad job.');
    [pathn, fn, extn] = fileparts(deblank(P(jj, :)));

    rand_fold(jj) = randi(10000000, 1);
    lc_path = strcat(lc_path_parent, num2str(rand_fold(jj)));
    ssh2_conn = ssh2_command(ssh2_conn, sprintf('mkdir %s', lc_path));
    ssh2_conn = scp_put(ssh2_conn, strcat(fn, extn), lc_path, pathn);

    lc_fn = strcat(lc_path, '/', fn, extn);
    cmd = [];
    if length(strfind(deblank(P(jj, :)), '_normalized.nii')) == 0
        aux_norm = strcat(fn, '_normalized.nii');
        cmd = sprintf('mri_normalize %s %s; ', lc_fn, strcat(lc_path, '/', aux_norm));
        lc_fn = strcat(lc_path, '/', aux_norm);
    end

    vari = sprintf('%s %s %d %d %s', lc_fn, launchpad_batch_templates, 0, check_aliasing, launchpad_defaults_mat);
    % Force single-threaded execution to eliminate DARTEL non-determinism
    % from heterogeneous PBS node CPU architectures (AVX/SSE/FMA variants
    % cause different floating-point summation ordering in iterative optimization).
    cmd = [cmd 'export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1; ' launchpad_runner ' ' launchpad_mcr_root ' ' vari ';'];
    cmd = sprintf('"%s"', cmd);
    [ssh2_conn, jobname{jj}, jobnum(jj)] = run_launchpad_cmd_return(...
        cmd, ssh2_conn, FS, queue_com, context, config); %#ok<AGROW>
    evidence = launchpad_evidence('submission', evidence, ...
        struct('jobname', jobname{jj}, 'jobnum', jobnum(jj)));
    context.job_number = jobnum(jj);
    pseudo_CT_output('SUCCESS', context, 'Launchpad job submitted (elapsed %s).', ...
        local_elapsed(toc(stage_started)));
end

shared_context = struct('log_files', {output_log_files}, 'scope', 'batch', ...
    'stage_index', 3, 'stage_count', 8, ...
    'subject_log_files', {output_log_files});
stage_started = tic;
pseudo_CT_output('INFO', shared_context, 'Waiting for remote Launchpad processing.');
ss_tot = check_launchpad_command_status(jobname, ssh2_conn, 10*60, 60, ...
    jobnum, shared_context, config);
pseudo_CT_output('SUCCESS', shared_context, ...
    'Remote processing wait completed (elapsed %s).', local_elapsed(toc(stage_started)));

for jj=1:size(P, 1)
    [pathn, fn, extn] = fileparts(deblank(P(jj, :))); %#ok<ASGLU>
    evidence = launchpad_evidence('polling', evidence, ...
        struct('exit_status', ss_tot(jj)));

    if ss_tot(jj) == 0
        % Legacy output: disp(sprintf('\nCopying Back images for subject %d of %d: %s\n', jj, size(P, 1), deblank(P(jj, :))));
        context = local_context(output_log_files, jj, size(P, 1), 4);
        stage_started = tic;
        pseudo_CT_output('INFO', context, 'Retrieving remote outputs.');
        lc_path = strcat(lc_path_parent, num2str(rand_fold(jj)));
        [ssh2_conn, comm_result] = ssh2_command(ssh2_conn, sprintf('ls %s/*', lc_path)); %#ok<ASGLU>
        ssh2_conn = scp_get(ssh2_conn, comm_result.', pathn);
        % Check that att_map.nii was produced on the cluster side.
        % A cluster job exiting 0 with no att_map.nii is a known failure mode
        % (e.g. subject-specific issues in the compiled Pseudo_CT_launchpad).
        if exist(fullfile(pathn, att_map_filename), 'file') ~= 2
            % Legacy output: fprintf(1, '[launchpad-debug] att_map.nii missing for subject %s despite job exit 0.\n', deblank(P(jj, :)));
            pseudo_CT_output('WARN', context, ...
                'Failure detail: remote job exited successfully but att_map.nii is missing.');
            ss_tot(jj) = 711;
        else
            pseudo_CT_output('SUCCESS', context, ...
                'Remote outputs retrieved (elapsed %s).', local_elapsed(toc(stage_started)));
        end
        evidence = launchpad_evidence('retrieval', evidence, struct(...
            'att_map_present', exist(fullfile(pathn, att_map_filename), 'file') == 2));
    else
        % Legacy output: disp(sprintf('\nSubject FAILED: %s\n', deblank(P(jj, :))));
        % Legacy output: fprintf(1, '[launchpad-debug] Job %d failed with exit code %d for subject %s\n', ...
        %     jobnum(jj), ss_tot(jj), deblank(P(jj, :)));
        context = local_context(output_log_files, jj, size(P, 1), 3);
        context.job_number = jobnum(jj);
    end
    if keep_tmp == 0
        ssh2_conn = ssh2_command(ssh2_conn, sprintf('rm -rf %s', strcat(lc_path_parent, num2str(rand_fold(jj)))));
        cleanup_state = 'remote-scratch-removed';
    else
        preserved_path = strcat(lc_path_parent, num2str(rand_fold(jj)));
        % Legacy output: fprintf(1, ['[keep-tmp] Preserved cluster scratch: %s\n', ...
        %             '[keep-tmp] To clean up later, run:\n', ...
        %             '           ssh %s ''rm -rf %s''\n'], ...
        %         preserved_path, ssh2_conn.hostname, preserved_path);
        pseudo_CT_output('INFO', context, 'Remote scratch was preserved.');
        pseudo_CT_output('INFO', context, '    %s', preserved_path);
        cleanup_state = 'remote-scratch-preserved';
    end
    evidence = launchpad_evidence('cleanup', evidence, struct('cleanup', cleanup_state));
    try
        launchpad_evidence('write', pathn, evidence);
    catch ME_evidence %#ok<CTCH>
        % Legacy output: fprintf(1, '[launchpad-diag] Could not save lifecycle evidence for %s: %s\n', fn, ME_evidence.message);
        pseudo_CT_output('WARN', context, 'Lifecycle evidence could not be saved: %s', ME_evidence.message);
    end
end

ssh2_conn = ssh2_close(ssh2_conn);

if clean_folder
    % Legacy output: disp(sprintf('Cleaning folders ... '));
    pseudo_CT_output('INFO', struct('log_files', {output_log_files}, 'scope', 'batch'), ...
        'Cleaning Launchpad staging folders.');
    for jj=1:size(P, 1)
        [pathn, fn, extn] = fileparts(deblank(P(jj, :))); %#ok<ASGLU>
        current_dir = pwd;
        cd(pathn);
        delete('*repos_params.mat')
        cd(current_dir);
        pseudo_CT_cleanup_intermediates(pathn);
    end
end

return
end

function context = local_context(log_files, subject_index, subject_count, stage_index)
context = struct('subject_index', subject_index, 'subject_count', subject_count, ...
    'stage_index', stage_index, 'stage_count', 8);
if length(log_files) >= subject_index
    context.log_file = log_files{subject_index};
end
end

function value = local_elapsed(seconds)
seconds = max(0, floor(seconds));
value = sprintf('%02d:%02d:%02d', floor(seconds / 3600), ...
    floor(rem(seconds, 3600) / 60), rem(seconds, 60));
end
