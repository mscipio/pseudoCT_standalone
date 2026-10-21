% Date: 02/09/2013;
% Name: atlas_based_attenuation_map.m;
% Function to create an attenuation map from a previously defined atlas,
% using Dartel non-rigid coregistration to coregister the images to the
% template. The output would perform an inverse warping, from atlas-space
% into the subject space, in order to generate the atlas-images (CT,
% attenuation map, MRs, etc) in subject space.
%
% Inputs: no inputs are required, in which case the user will be prompted
%         to select the original images to proceed. However, some input
%         variables could be passed to avoid further user interaction:
%         - varargin{1} = P: Original images to be coregistered to the atlas.
%                        It needs to be a string to be readable (as from
%                        spm_select);
%         - varargin{2} = dir_batch_templates: the folder where the
%                         templates and the batch templates are to run the
%                         program. If not present, or left blank (''), a preselected folder will
%                         be automatically chosen!
%         - varargin{3} = ssh2_conn: struct with fields (username, password, hostname); where
%         hostname is the IP address of the computer hosting the FreeSurfer
%         software.
%         - varargin{4} = check_aliasing; = 0: do NOT check (and correct if
%         needed) for aliasing (in case the user already is certain that no
%         aliasing is happening on the image); = 1: check (and correct if
%         needed for aliasing). If correcting, user will need to manually
%         confirm that the automatic correction was propery done.
%         - varargin{5} = selected profile config for the existing
%         5-argument contract, or optional output context otherwise.
%         - varargin{6} = optional recenter override when varargin{7} is the
%         selected profile config.
%         - varargin{6}/{7} = selected profile config for the existing
%         6-argument contract, or the extended 7-argument contract.
%
% Outputs: - Pf: array of strings containing the names of the new created
% atlases in subject space:
%          - att_map: the attenuation map, converted from the CT-atlas.
%          - CT_atlas: the CT-atlas coregistered back to subject space.
%          - MPRAGE_atlas: the MPRAGE-atlas  "    "    "    "      "  .
%          - UTE1_atlas: the UTE1-atlas    "      "    "    "      "  .
%          - UTE2_atlas: the UTE2-atlas    "      "    "    "      "  .
%          - head_mask_atlas: the head mask  "    "    "    "      "  .
%
%          - ssh2_conn: the ssh connexion to Brain-Vision
% To use: [Pf] = atlas_based_attenuation_map(P, dir_batch_templates, ssh2_conn, check_aliasing)
%
% Please, if you use this program (or parts of it), please, quote the
% paper:
%
% D. Izquierdo-Garcia, A.E. Hansen, S. F�rster, D. Benoit, S. Schachoff, S. F�rst, K.T. Chen, D.B. Chonde, and C. Catana.
% An SPM8-based Approach for Attenuation Correction Combining Segmentation and Non-rigid Template Formation: Application to Simultaneous PET/MR Brain Imaging. JNM. 2014. In press.
%
% By David Izquierdo-Garcia.
% Athinoula A. Martinos Center.
% Harvard University / Mass. General Hospital. Boston.
%
% 04/09/2013; Newer version including the call to FreeSurfer commands to do
% the intensity normalization. Only MPRAGEs should be included here as
% UTE's should be avoided at this point.
% Code version included in a text file!
% 05/28/2013: New 3 argument that could be used as input for ssh login so
% that we could batch the subjects.
% 06/21/2013: v.1.4. Using launchpad to run FreeSurfer commands!
% 08/26/2013: v.1.5. Solving bug when running parallel sessions.
% Feb/7/2014: v.1.6: Increasing the attenuation mask to reduce Nose-job problems!);
% Mar/13/2014: v.1.6.1: Improving the Nose-job solution!
% Apr/21/2014: v.1.6.2: including username in /cluster/scratch/monday
%           folder for generating a random subfoder;
% July/22/2014: v.1.7: Forcing the MPRAGE mask to contain only the biggest
%        ROI and avoiding other small rois (possible from aliasing that is
%        overlapping, for instance).
% Sept/3/2014: v.1.8: Moving the MPRAGE image into the center of the image
%        so that the normalize step does not chop the nose/back of the
%        subject. For the inital MPRAGE mask, we reduce the threshold from
%        20 to 15;
% Sept/11/2014: v.1.8.1: including automatic correction of aliasing (if
%        selected by the user) in the script for centering check of the image;
% Dec/9/2014: v.2.0: allowing deployed version.
% Apr/5/2016: v.2.1: printing QC image: fused images (MR and pseudo-CTs) of
%        all 3 planes, and also MIP images on all 3 planes.
% July/28/2016: v.2.2: Integration of Mike's ssh_login to standardize the
%        use of ssh2_conn.
% Sept/23/2016: v.2.3: Improving the subject mask using the
%        MPRAGE_normalized mask!
% Dec/17/2017: v.2.4: Allows local connections to 127.0.0.1 to run FS
%        commands locally!
% May/28/2026: v.2.5: Repackage the workflow as a standalone,
%        redistributable package that can run locally while preserving the
%        option to use the historical compiled v2.0 Launchpad backend.


function [Pf] = atlas_based_attenuation_map(varargin)

% Resolve code version from CHANGELOG.md line 1 at the repo root; fall back to
% hardcoded value if the file cannot be read.
code_version = '2.8.4';  % fallback (resolved in shared helpers; kept for provenance) %#ok<NASGU>
try
    root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    fid = fopen(fullfile(root_dir, 'CHANGELOG.md'), 'r');
    if fid ~= -1
        v = strtrim(fgetl(fid));
        fclose(fid);
        if ~isempty(v) && ischar(v)
            code_version = v;
        end
    end
catch  %#ok<CTCH>
end

Pf = ''; % In case program quits before finishing!
if nargin < 5 || nargin > 7 || ~isstruct(varargin{end})
    error('pseudo_CT:ProfileRequired', ...
        'atlas_based_attenuation_map requires the selected profile config.');
end
P = varargin{1};
dir_batch_templates = varargin{2};
ssh2_conn = varargin{3};
check_aliasing = varargin{4};
config = varargin{end};
output_context = struct();
recenter_override = [];
if nargin >= 6
    output_context = varargin{5};
end
if nargin == 7
    recenter_override = varargin{6};
end
autom_select_folder = isempty(dir_batch_templates); %#ok<NASGU> % effective atlas selection owned by shared prepare
ssh_ask_login = ~isstruct(ssh2_conn);

% % Ask the user to agree with the terms:
% answ_dlg = questdlg(sprintf('This is still Unpublished work!\nDo Not include in publications until we publish the method (Then reference it!)\nIf you agree with this, click Yes, if not, click No'), 'UNPUBLISHED WORK!!!', 'Yes', 'No', 'No');
% switch answ_dlg
%     case 'No'
%         warndlg('Please, contact David Izquierdo-Garcia for details!', 'Program quit!');
%         return
%     otherwise
% end

% T002 shared boundary: pre-normalization preparation (optional reslice,
% normalized/moved suffix gates, correct_aliasing with R2019+ gate and
% success/partial/early-return semantics). Headless remains default-off;
% existing callers without config.headless/output_context.headless observe
% unchanged behavior.
[prepared_P, prepare_handoff, prepare_early_return, fh] = pseudo_CT_current_prepare( ...
    P, dir_batch_templates, check_aliasing, config, output_context, recenter_override);
if prepare_early_return
    return;
end
P = prepared_P;
dir_batch_templates = prepare_handoff.atlas_dir;
nf = size(P, 1);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now let's put the images into Brain-Vision (@172.20.180.53) and run
% FreeSurfer
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Let's ask the user to introduce his username and password (with
% confirmation):
stage_started = tic;
stage_context = local_stage_context(output_context, 2);
pseudo_CT_output('INFO', stage_context, 'Normalizing MPRAGE with FreeSurfer.');
if length(strfind(deblank(P(1, :)), '_normalized.nii')) == 0
%     if ssh_ask_login | length(varargin{3}) ~= 3
%         [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
%             'WindowName', 'Enter your Martinos Login and Password to connect to Brain-Vision and use FreeSurfer!');
%         % Now let's copy the file (or files) to the server:
%         % if one would like to upload a few files sequentilly, use a cell array
%         %HOSTNAME = '172.20.180.53'; % Address of Brain-Vision computer!
%     else
%         auxi = varargin{3};
%         if length(auxi) ~= 3
%             disp('There should be 3 strings in argument 3: {username, password, hostname}');
%             return;
%         end
%         USERNAME = auxi{1};
%         PASSWORD = auxi{2};
%         HOSTNAME = auxi{3};
%         clear auxi
%     end
    if ssh_ask_login ||  ~isstruct(varargin{3})
        ssh2_conn = ssh_login_pseudo_CT(config);
    else
        ssh2_conn = varargin{3};
    end
    if ~isfield(ssh2_conn, 'hostname') || isempty(ssh2_conn.hostname)
        ssh2_conn.hostname = config.normalization.host;
    end
    if ~isfield(ssh2_conn, 'username') || isempty(ssh2_conn.username)
        ssh2_conn.username = getenv('USER');
        if isempty(ssh2_conn.username)
            ssh2_conn.username = getenv('LOGNAME');
        end
        if isempty(ssh2_conn.username)
            ssh2_conn.username = 'local';
        end
    end
    if ~isfield(ssh2_conn, 'password') || isempty(ssh2_conn.password)
        ssh2_conn.password = '';
    end
    USERNAME = ssh2_conn.username;
    PASSWORD = ssh2_conn.password;
    HOSTNAME = ssh2_conn.hostname;
    is_local_host = strcmp(HOSTNAME, '127.0.0.1') || strcmpi(HOSTNAME, 'localhost');

    if is_local_host
        % Legacy output: disp('Preparing local FreeSurfer normalization commands ...');
    else
        % Legacy output: disp('Starting the ssh connection to run the Normalization process  ... (be patient!)');
        ssh2_conn = ssh2_config(HOSTNAME,USERNAME,PASSWORD);
    end
    if is_local_host
        host_fold = fileparts(deblank(P(1, :)));
    else
        host_fold = config.normalization.host_folder;
    end
    if ~strcmp(host_fold(end), '/'), host_fold = [host_fold, '/']; end
    lc_path = strcat(host_fold, ssh2_conn.username, '/'); % This is the Launchpad folder where to execute the commands!
    ssh2_conn = ssh2_command_david(ssh2_conn, sprintf('mkdir %s', lc_path));
    clear aux
    % Generate a random folder:
    rand_fold = randi(10000000, 1);
    lc_path = strcat(lc_path, num2str(rand_fold));
    % Create the folder:
    ssh2_conn = ssh2_command_david(ssh2_conn, sprintf('mkdir %s', lc_path));
    for ii=1:nf
        [pathr, fnr, extr] = fileparts(deblank(P(ii, :)));
        if strcmp(extr(end-1:end), ',1'), extr = extr(1:end-2); end
        aux(ii) = {strcat(fnr, extr)};
    end
    ssh2_conn = scp_put_david(ssh2_conn,aux, lc_path, pathr);
    % Now let's run the mri_normalize command, after sourcing FreeSurfer:
    for ii=1:nf
        aux_norm(ii) = {strcat(aux{ii}(1:end-4), '_normalized.nii')};
        cmd = sprintf('"mri_normalize %s %s"', strcat(lc_path, '/', aux{ii}), strcat(lc_path, '/', aux_norm{ii}));
        if ~strcmpi(config.normalization.cluster, 'yes')
            cmd = cmd(2:end-1); % Cut the " ";
            [sts] = run_normalization_cmd(cmd, ssh2_conn, stage_context, config);
        else
            [sts] = run_launchpad_cmd(cmd, ssh2_conn, config);
        end
        if sts ~= 0
            % Legacy output: disp(sprintf('Normalization failed for:\n%s', aux{ii}));
            % Legacy output: disp(sprintf('Temporary files were left in:\n%s', lc_path));
            pseudo_CT_output('ERROR', stage_context, 'FreeSurfer normalization failed.');
            pseudo_CT_output('INFO', stage_context, '    %s', lc_path);
            if ~is_local_host
                ssh2_conn = ssh2_close(ssh2_conn);
            end
            return;
        end
        %ssh2_conn = ssh2_command(ssh2_conn, sprintf('%s; mri_normalize %s %s', source_command, aux{ii}, aux_norm{ii}), 1);
    end
    % Let's transfer them back to the subject's folder:
    ssh2_conn = scp_get_david(ssh2_conn, aux_norm, pathr, lc_path);
    % And let's erase all the images:
    for ii=1:nf
        ssh2_conn = ssh2_command_david(ssh2_conn, sprintf('rm %s', fullfile(lc_path, aux{ii})));
        ssh2_conn = ssh2_command_david(ssh2_conn, sprintf('rm %s', fullfile(lc_path, aux_norm{ii})));
        % Let's update the new images' filenames:
        auxi = fullfile(pathr, aux_norm{ii});
        P(ii, 1:length(auxi)) = auxi;
    end
    % Let's erase the random folder just created:
    ssh2_conn = ssh2_command_david(ssh2_conn, sprintf('rm -rf %s', lc_path));
    if ~is_local_host
        ssh2_conn = ssh2_close(ssh2_conn);
    end
end

pseudo_CT_output('SUCCESS', stage_context, 'MPRAGE normalization completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% T002 shared boundary: post-normalization computation (MNI/PCA/masking/
% segmentation/bone/DARTEL/inverse warp/reslice/attenuation/QC) with
% preserved P_orig affine semantics. Headless remains default-off here;
% mlsc_current_payload explicitly opts in.
Pf = pseudo_CT_current_compute(P, dir_batch_templates, config, output_context, fh);


return
end

function context = local_stage_context(context, stage_index)
context.stage_index = stage_index;
context.stage_count = 8;
end

function value = local_elapsed(seconds)
seconds = max(0, floor(seconds));
value = sprintf('%02d:%02d:%02d', floor(seconds / 3600), ...
    floor(rem(seconds, 3600) / 60), rem(seconds, 60));
end

function value = local_normalize_flag(value, default_value)
if nargin < 1 || isempty(value)
    value = default_value;
elseif ischar(value)
    normalized = lower(strtrim(value));
    if strcmp(normalized, 'yes') || strcmp(normalized, 'true') || ...
            strcmp(normalized, 'on') || strcmp(normalized, '1')
        value = true;
    elseif strcmp(normalized, 'no') || strcmp(normalized, 'false') || ...
            strcmp(normalized, 'off') || strcmp(normalized, '0')
        value = false;
    else
        error('pseudo_CT:InvalidRecentering', ...
            'Recentering must be Yes/No or a scalar logical 0 or 1.');
    end
elseif (isnumeric(value) || islogical(value)) && isscalar(value) && ...
        (double(value) == 0 || double(value) == 1)
    value = logical(value);
else
    error('pseudo_CT:InvalidRecentering', ...
        'Recentering must be Yes/No or a scalar logical 0 or 1.');
end
end

function supported = local_correct_aliasing_supported()
release = version('-release');
supported = false;
if ischar(release)
    release_text = release;
    if ~isempty(release_text) && ...
            (release_text(1) == 'R' || release_text(1) == 'r')
        release_text = release_text(2:end);
    end
    if length(release_text) >= 4
        release_year = str2double(release_text(1:4));
        supported = ~isnan(release_year) && release_year >= 2019;
    end
end
end
