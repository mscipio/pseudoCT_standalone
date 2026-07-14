% Date: May/28/2026;
% Standalone Launchpad backend that mirrors the old compiled pseudo-CT path.

function [ssh2_conn, jobname, rand_fold, ss_tot] = batch_pseudo_CT_launchpad(P, ssh_log, varargin)

clean_folder = 1;
keep_tmp = 0;
check_aliasing = 1;

if length(P) == 0
    P = spm_select(Inf, 'any', 'Choose the subjects to run Pseudo-CT on cluster!');
end
if ~iscell(ssh_log) || length(ssh_log) ~= 3
    [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
        'WindowName', 'Enter your Martinos Login and Password to connect to Launchpad and use FreeSurfer!');
    HOSTNAME = defaults_pseudo_CT_launchpad('HOSTNAME');
    ssh_log = {USERNAME, PASSWORD, HOSTNAME};
    clear USERNAME PASSWORD HOSTNAME
end

fix_args = 2;
if nargin > fix_args && rem(nargin-fix_args, 2) == 0
    for ii=1:2:(nargin-fix_args)
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
elseif rem(nargin-fix_args, 2) ~= 0
    disp(sprintf('The total number of input variables must be: (%d fix + multiples of 2 for extra parameters)!!!', fix_args));
    return
end

FS = 1;
% Queue selection: defaults_pseudo_CT_launchpad('queue_name') takes
% priority (e.g. 'p60' for faster scheduling). If empty, fall back to
% the hardcoded heuristic (-q max100 for >100 subjects, default otherwise).
queue_override = defaults_pseudo_CT_launchpad('queue_name');
if ~isempty(queue_override)
    queue_com = ['-q ', queue_override];
elseif size(P, 1) > 100
    queue_com = '-q max100';
else
    queue_com = '';
end

att_map_filename = 'att_map.nii';

ssh2_conn = ssh2_config(ssh_log{3}, ssh_log{1}, ssh_log{2});
host_folder = defaults_pseudo_CT_launchpad('host_folder');
if ~strcmp(host_folder(end), '/')
    host_folder = [host_folder, '/'];
end
lc_path_parent = strcat(host_folder, ssh2_conn.username, '/');
ssh2_conn = ssh2_command(ssh2_conn, sprintf('mkdir %s', lc_path_parent));

launchpad_batch_templates = defaults_pseudo_CT_launchpad('launchpad_batch_templates');
launchpad_defaults_mat = defaults_pseudo_CT_launchpad('launchpad_defaults_mat');
launchpad_runner = defaults_pseudo_CT_launchpad('launchpad_runner');
launchpad_mcr_root = defaults_pseudo_CT_launchpad('launchpad_mcr_root');

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
    cmd = [cmd launchpad_runner ' ' launchpad_mcr_root ' ' vari ';'];
    cmd = sprintf('"%s"', cmd);
    [ssh2_conn, jobname{jj}, jobnum(jj)] = run_launchpad_cmd_return(cmd, ssh2_conn, FS, queue_com); %#ok<AGROW>
end

ss_tot = check_launchpad_command_status(jobname, ssh2_conn, 10*60, 60, jobnum);

for jj=1:size(P, 1)
    [pathn, fn, extn] = fileparts(deblank(P(jj, :))); %#ok<ASGLU>

    % --- Diagnostic: capture PBS job logs from cluster (always) ---
    % The compiled Launchpad binary is opaque — PBS stdout/stderr are
    % the only runtime evidence for both successes and failures.
    % Martinos cluster writes PBS logs to /pbs/<user>/ as
    % <jobname>.o<N> (stdout) and <jobname>.e<N> (stderr).
    try
        pbs_cmd = sprintf('ls /pbs/%s/*o%d /pbs/%s/*e%d 2>/dev/null', ...
            ssh2_conn.username, jobnum(jj), ssh2_conn.username, jobnum(jj));
        [ssh2_conn, pbs_result] = ssh2_command(ssh2_conn, pbs_cmd);
        if ~isempty(pbs_result)
            ssh2_conn = scp_get(ssh2_conn, pbs_result.', pathn);
            for kk = 1:length(pbs_result)
                [~, pbs_fn, pbs_ext] = fileparts(pbs_result{kk});
                src = fullfile(pathn, [pbs_fn pbs_ext]);
                dst = fullfile(pathn, sprintf('%s_launchpad_%s%s', fn, pbs_fn, pbs_ext));
                if exist(src, 'file') == 2
                    try
                        movefile(src, dst);
                    catch  %#ok<CTCH>
                        fprintf(1, '[launchpad-diag] Could not rename PBS log %s (may already exist)\n', [pbs_fn pbs_ext]);
                    end
                end
            end
            fprintf(1, '[launchpad-diag] Saved PBS job logs for subject %s in %s\n', fn, pathn);
        end
    catch ME_pbs  %#ok<CTCH>
        fprintf(1, '[launchpad-diag] Could not fetch PBS logs for subject %s: %s\n', fn, ME_pbs.message);
    end

    if ss_tot(jj) == 0
        disp(sprintf('\nCopying Back images for subject %d of %d: %s\n', jj, size(P, 1), deblank(P(jj, :))));
        lc_path = strcat(lc_path_parent, num2str(rand_fold(jj)));
        [ssh2_conn, comm_result] = ssh2_command(ssh2_conn, sprintf('ls %s/*', lc_path)); %#ok<ASGLU>
        ssh2_conn = scp_get(ssh2_conn, comm_result.', pathn);
        % Check that att_map.nii was produced on the cluster side.
        % A cluster job exiting 0 with no att_map.nii is a known failure mode
        % (e.g. subject-specific issues in the compiled Pseudo_CT_launchpad).
        % PBS logs were already captured above — see pathn.
        if exist(fullfile(pathn, att_map_filename), 'file') ~= 2
            fprintf(1, '[launchpad-debug] att_map.nii missing for subject %s despite job exit 0.\nSee PBS logs in: %s\n', deblank(P(jj, :)), pathn);
            % Print PBS log heads for immediate console feedback
            log_files = dir(fullfile(pathn, sprintf('%s_launchpad_*', fn)));
            for kk = 1:min(length(log_files), 2)
                fid = fopen(fullfile(pathn, log_files(kk).name), 'r');
                if fid ~= -1
                    log_txt = fread(fid, 4096, '*char')';
                    fclose(fid);
                    fprintf(1, '[launchpad-debug] PBS log %s (head):\n%s\n', log_files(kk).name, log_txt);
                end
            end
        end
    else
        disp(sprintf('\nSubject FAILED: %s\n', deblank(P(jj, :))));
        fprintf(1, '[launchpad-debug] Job %d failed with exit code %d — see PBS logs in %s\n', ...
            jobnum(jj), ss_tot(jj), pathn);
    end
    if keep_tmp == 0
        ssh2_conn = ssh2_command(ssh2_conn, sprintf('rm -rf %s', strcat(lc_path_parent, num2str(rand_fold(jj)))));
    else
        preserved_path = strcat(lc_path_parent, num2str(rand_fold(jj)));
        fprintf(1, ['[keep-tmp] Preserved cluster scratch: %s\n', ...
                    '[keep-tmp] To clean up later, run:\n', ...
                    '           ssh %s ''rm -rf %s''\n'], ...
                preserved_path, ssh2_conn.hostname, preserved_path);
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