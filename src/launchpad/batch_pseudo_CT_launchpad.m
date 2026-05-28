% Date: May/28/2026;
% Standalone Launchpad backend that mirrors the old compiled pseudo-CT path.

function [ssh2_conn, jobname, rand_fold, ss_tot] = batch_pseudo_CT_launchpad(P, ssh_log, varargin)

clean_folder = 1;
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
if size(P, 1) > 100
    queue_com = '-q max100';
else
    queue_com = '';
end

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
    if ss_tot(jj) == 0
        disp(sprintf('\nCopying Back images for subject %d of %d: %s\n', jj, size(P, 1), deblank(P(jj, :))));
        [pathn, fn, extn] = fileparts(deblank(P(jj, :))); %#ok<ASGLU>
        lc_path = strcat(lc_path_parent, num2str(rand_fold(jj)));
        [ssh2_conn, comm_result] = ssh2_command(ssh2_conn, sprintf('ls %s/*', lc_path)); %#ok<ASGLU>
        ssh2_conn = scp_get(ssh2_conn, comm_result.', pathn);
    else
        disp(sprintf('\nSubject FAILED: %s\n', deblank(P(jj, :))));
    end
    ssh2_conn = ssh2_command(ssh2_conn, sprintf('rm -rf %s', strcat(lc_path_parent, num2str(rand_fold(jj)))));
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