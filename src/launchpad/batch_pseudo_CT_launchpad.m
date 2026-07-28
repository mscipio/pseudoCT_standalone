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
            otherwise
                disp('Unkown parameter!!');
                return
        end
    end
elseif rem(num_extra_args, 2) ~= 0
    disp(sprintf('The total number of input variables must be: (%d fix + multiples of 2 for extra parameters)!!!', fix_args));
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
    disp(sprintf('Working on subject %d of %d:\n%s\n', jj, size(P, 1), deblank(P(jj, :))));
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
        cmd, ssh2_conn, FS, queue_com, config); %#ok<AGROW>
    evidence = launchpad_evidence('submission', evidence, ...
        struct('jobname', jobname{jj}, 'jobnum', jobnum(jj)));
end

ss_tot = check_launchpad_command_status(jobname, ssh2_conn, 10*60, 60, ...
    jobnum, config);

for jj=1:size(P, 1)
    [pathn, fn, extn] = fileparts(deblank(P(jj, :))); %#ok<ASGLU>
    evidence = launchpad_evidence('polling', evidence, ...
        struct('exit_status', ss_tot(jj)));

    if ss_tot(jj) == 0
        disp(sprintf('\nCopying Back images for subject %d of %d: %s\n', jj, size(P, 1), deblank(P(jj, :))));
        lc_path = strcat(lc_path_parent, num2str(rand_fold(jj)));
        [ssh2_conn, comm_result] = ssh2_command(ssh2_conn, sprintf('ls %s/*', lc_path)); %#ok<ASGLU>
        ssh2_conn = scp_get(ssh2_conn, comm_result.', pathn);
        % Check that att_map.nii was produced on the cluster side.
        % A cluster job exiting 0 with no att_map.nii is a known failure mode
        % (e.g. subject-specific issues in the compiled Pseudo_CT_launchpad).
        if exist(fullfile(pathn, att_map_filename), 'file') ~= 2
            fprintf(1, '[launchpad-debug] att_map.nii missing for subject %s despite job exit 0.\n', deblank(P(jj, :)));
        end
        evidence = launchpad_evidence('retrieval', evidence, struct(...
            'att_map_present', exist(fullfile(pathn, att_map_filename), 'file') == 2));
    else
        disp(sprintf('\nSubject FAILED: %s\n', deblank(P(jj, :))));
        fprintf(1, '[launchpad-debug] Job %d failed with exit code %d for subject %s\n', ...
            jobnum(jj), ss_tot(jj), deblank(P(jj, :)));
    end
    if keep_tmp == 0
        ssh2_conn = ssh2_command(ssh2_conn, sprintf('rm -rf %s', strcat(lc_path_parent, num2str(rand_fold(jj)))));
        cleanup_state = 'remote-scratch-removed';
    else
        preserved_path = strcat(lc_path_parent, num2str(rand_fold(jj)));
        fprintf(1, ['[keep-tmp] Preserved cluster scratch: %s\n', ...
                    '[keep-tmp] To clean up later, run:\n', ...
                    '           ssh %s ''rm -rf %s''\n'], ...
                preserved_path, ssh2_conn.hostname, preserved_path);
        cleanup_state = 'remote-scratch-preserved';
    end
    evidence = launchpad_evidence('cleanup', evidence, struct('cleanup', cleanup_state));
    try
        launchpad_evidence('write', pathn, evidence);
    catch ME_evidence %#ok<CTCH>
        fprintf(1, '[launchpad-diag] Could not save lifecycle evidence for %s: %s\n', fn, ME_evidence.message);
    end
end

ssh2_conn = ssh2_close(ssh2_conn);

if clean_folder
    disp(sprintf('Cleaning folders ... '));
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
