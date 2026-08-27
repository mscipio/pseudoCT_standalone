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
%         - varargin{5} = optional output context.
%         - varargin{6} = selected profile config.
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
code_version = '2.8.2';  % fallback
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
if nargin < 5 || nargin > 6 || ~isstruct(varargin{end})
    error('pseudo_CT:ProfileRequired', ...
        'atlas_based_attenuation_map requires the selected profile config.');
end
P = varargin{1};
dir_batch_templates = varargin{2};
ssh2_conn = varargin{3};
check_aliasing = varargin{4};
config = varargin{end};
output_context = struct();
if nargin == 6
    output_context = varargin{5};
end
autom_select_folder = isempty(dir_batch_templates);
ssh_ask_login = ~isstruct(ssh2_conn);

% % Ask the user to agree with the terms:
% answ_dlg = questdlg(sprintf('This is still Unpublished work!\nDo Not include in publications until we publish the method (Then reference it!)\nIf you agree with this, click Yes, if not, click No'), 'UNPUBLISHED WORK!!!', 'Yes', 'No', 'No');
% switch answ_dlg
%     case 'No'
%         warndlg('Please, contact David Izquierdo-Garcia for details!', 'Program quit!');
%         return
%     otherwise
% end

if autom_select_folder
    dir_batch_templates = config.atlas_root;
end


if isdir(fullfile(dir_batch_templates, 'ganymed-ssh2-build250'))
    a = javaclasspath;
    if (length(a) == 0) || (length(strfind(a{1}, 'ganymed-ssh2-build250')) == 0)
        javaaddpath(fullfile(dir_batch_templates, 'ganymed-ssh2-build250', 'ganymed-ssh2-build250.jar'));
    end
end

% Look for the Atlases!
list_atlas = dir(fullfile(dir_batch_templates, '*Atlas*.nii'));
if length(list_atlas) == 0
    % Legacy output: disp(sprintf('No *Atlas*.nii files were found on the folder: \n%s', fullfile(dir_batch_templates)));
    pseudo_CT_output('ERROR', output_context, 'No atlas NIfTI files were found.');
    pseudo_CT_output('INFO', output_context, '    %s', dir_batch_templates);
    return;
end

% To work only with the MPRAGE even if there are more files available!
P = P(1, :);

nf = size(P, 1); % nf = The total number of files to use.

%fh=openfig(fullfile(spm('Dir'),'spm_Interactive.fig'),'new','visible'); % Open the spm figure window to see how things are going!
if ~isdeployed
    fh = spm('CreateIntWin','on');
    try
        set(fh, 'Visible', 'off');
    catch
    end
else
    try
        fh=openfig('spm_Interactive.fig','new','visible');
        set(fh, 'Visible', 'off');
    catch
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Need to check whether the images are all in the same space! If not, ask
% the user to reslice them so that they all are in the same space.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
V = spm_vol(P);
resl = 1; % Do not reslice unless necessary:

% Define the flags for reslicing:
flg.mean  = 0; % Don't create a mean image;
flg.which = 1; % Don't reslice the first image;
flg.mask  = 0; % Don't mask;
flg.interp = 7; % 7th degree bspline;
flg.wrap = [0 0 0]; % No wrapping;

for ii=2:nf
    if sum(V(ii).dim ~= V(ii-1).dim) > 0, resl = 1; break; end
end
if resl & nf > 1
    % Legacy output: disp(sprintf('The images need to be resliced into the same space (your first selected image)!!:\n%s', deblank(P(1, :))));
    pseudo_CT_output('INFO', output_context, 'Reslicing inputs into MPRAGE space.');
    % The first image would be considered as reference, and the last as
    % source and the rest os other:
    job.ref = {deblank(P(1, :))}; job.source = {deblank(P(nf, :))}; job.other = {''};
    for ii=nf:-1:2
        job.other{ii-1, 1} = P(ii, :);
    end
    job.eoptions = spm_get_defaults('coreg.estimate'); job.roptions = spm_get_defaults('coreg.write');
    job.roptions.interp = 7; % 7th degree bspline;
    evalc('spm_run_coreg_estwrite(job);'); % Estimate and reslice!
    %spm_reslice(P, flg); % Reslice only!
    for ii=2:nf
        [pathr,fnr,extr] = fileparts(deblank(P(ii, :)));
        aux = strcat(pathr, filesep,'r', fnr, extr);
        P(ii, 1:length(aux)) = aux; % Just in case the new name is longer than the matrix P!
    end
    V = spm_vol(P); % Update the volume content with the new files!
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% v.1.8: Let's try to get the subject into the center of the image to avoid
% that the normalization process cut the nose
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
recenter_before_normalization = ...
    strcmpi(config.recenter_before_normalization, 'yes');

aliasing_requested = logical(check_aliasing);
recentering_requested = recenter_before_normalization;
gate_condition = length(strfind(deblank(P(1, :)), '_normalized.nii')) == 0 & ...
                 length(strfind(deblank(P(1, :)), '_moved.nii')) == 0;

if recentering_requested && gate_condition
    % Use external correct_aliasing package for both alias correction and centering
    [path_in, name_in, ext_in] = fileparts(deblank(P(1, :)));
    output_path = fullfile(path_in, [name_in, '_corrected', ext_in]);

    result = correct_aliasing(deblank(P(1, :)), output_path, ...
        'AliasCorrection', aliasing_requested, ...
        'Centering', recentering_requested, ...
        'Overwrite', true);

    % Defensively normalize facade result
    result_status = '';
    result_message = '';
    result_outputs = {};
    result_details = struct();
    if isstruct(result)
        if isfield(result, 'status')
            if ischar(result.status)
                result_status = strtrim(result.status);
            elseif isnumeric(result.status) && ~isempty(result.status)
                result_status = strtrim(char(result.status));
            end
        end
        if isfield(result, 'message')
            if ischar(result.message)
                result_message = strtrim(result.message);
            elseif isnumeric(result.message) && ~isempty(result.message)
                result_message = strtrim(char(result.message));
            end
        end
        if isfield(result, 'outputs') && iscell(result.outputs)
            result_outputs = result.outputs;
        end
        if isfield(result, 'details') && isstruct(result.details)
            result_details = result.details;
        end
    end

    accepted = strcmpi(result_status, 'success') || strcmpi(result_status, 'partial');
    has_output = false;
    if ~isempty(result_outputs)
        candidate = result_outputs{1};
        if ischar(candidate) && ~isempty(strtrim(candidate))
            has_output = true;
        end
    end

    if accepted && has_output
        P = result.outputs{1};
    end

    % Log recentering outcome
    stage_ctx = local_stage_context(output_context, 1);
    if ~recentering_requested
        pseudo_CT_output('INFO', stage_ctx, '[recentering] Skipped as configured.');
    elseif accepted && has_output
        recentering_performed = [];
        if isfield(result_details, 'centering') && isstruct(result_details.centering) && isfield(result_details.centering, 'performed')
            raw = result_details.centering.performed;
            if islogical(raw)
                recentering_performed = raw;
            elseif isnumeric(raw) && ~isempty(raw)
                recentering_performed = logical(raw(1));
            elseif ischar(raw)
                trimmed = strtrim(raw);
                if strcmpi(trimmed, 'true') || strcmp(trimmed, '1')
                    recentering_performed = true;
                elseif strcmpi(trimmed, 'false') || strcmp(trimmed, '0')
                    recentering_performed = false;
                end
            end
        end
        if isempty(recentering_performed)
            pseudo_CT_output('WARN', stage_ctx, '[recentering] Result unavailable.');
        elseif recentering_performed
            pseudo_CT_output('SUCCESS', stage_ctx, '[recentering] Successfully applied.');
        else
            pseudo_CT_output('INFO', stage_ctx, '[recentering] Not required.');
        end
    else
        error_msg = result_message;
        if isempty(error_msg)
            error_msg = result_status;
        end
        if isempty(error_msg)
            error_msg = 'unknown';
        end
        pseudo_CT_output('ERROR', stage_ctx, '[recentering] Failed: %s.', error_msg);
    end

    % Log aliasing outcome
    if ~aliasing_requested
        pseudo_CT_output('INFO', stage_ctx, '[aliasing correction] Skipped as configured.');
    elseif accepted && has_output
        aliasing_performed = [];
        if isfield(result_details, 'alias_correction') && isstruct(result_details.alias_correction) && isfield(result_details.alias_correction, 'performed')
            raw = result_details.alias_correction.performed;
            if islogical(raw)
                aliasing_performed = raw;
            elseif isnumeric(raw) && ~isempty(raw)
                aliasing_performed = logical(raw(1));
            elseif ischar(raw)
                trimmed = strtrim(raw);
                if strcmpi(trimmed, 'true') || strcmp(trimmed, '1')
                    aliasing_performed = true;
                elseif strcmpi(trimmed, 'false') || strcmp(trimmed, '0')
                    aliasing_performed = false;
                end
            end
        end
        if isempty(aliasing_performed)
            pseudo_CT_output('WARN', stage_ctx, '[aliasing correction] Result unavailable.');
        elseif aliasing_performed
            pseudo_CT_output('SUCCESS', stage_ctx, '[aliasing correction] Successfully applied.');
        else
            pseudo_CT_output('INFO', stage_ctx, '[aliasing correction] Not required.');
        end
    else
        error_msg = result_message;
        if isempty(error_msg)
            error_msg = result_status;
        end
        if isempty(error_msg)
            error_msg = 'unknown';
        end
        pseudo_CT_output('ERROR', stage_ctx, '[aliasing correction] Failed: %s.', error_msg);
    end

    % Preserve early-return behavior
    if ~accepted || ~has_output
        return;
    end
elseif ~recentering_requested
    stage_ctx = local_stage_context(output_context, 1);
    pseudo_CT_output('INFO', stage_ctx, '[recentering] Skipped as configured.');
    if aliasing_requested
        pseudo_CT_output('INFO', stage_ctx, '[aliasing correction] Skipped because pre-normalization preprocessing is disabled.');
    else
        pseudo_CT_output('INFO', stage_ctx, '[aliasing correction] Skipped as configured.');
    end
end


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
% Now reorient all images to make them close to the MNI template (ch2.nii)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
stage_started = tic;
stage_context = local_stage_context(output_context, 3);
pseudo_CT_output('INFO', stage_context, 'Aligning MPRAGE and creating subject mask.');
P_orig = P; % Let's save the original image filenames as we will need them to use their .mat to reposition the att-map!
P = move_image_2_MNI(P_orig, fullfile(dir_batch_templates, 'ch2.nii'), ...
    stage_context, config);
% Decompose the first image (reference to warp everthing into this image)
% into its fileparts:
[paths,fns,exts] = fileparts(deblank(P(1, :)));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now smooth the image to create a better subject mask avoiding noise!
% And apply that mask to the MPRAGE*normalized image to avoid the noise in
% the segmentation!!
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Only the first image need to be smoothed to create the mask:
[pathm,fnm,extm] = fileparts(deblank(P(1, :)));
sm_fn = fullfile(pathm, strcat('s',fnm,extm)); % The new smoothed file filename!
spm_smooth(P(1, :), sm_fn, 4);
Ims = spm_read_vols(spm_vol(sm_fn));
[~, subj_mask] = head_mask_mprage(Ims, 15); % Create the mask!; Before v1.8 it was 20;
mm = imdilate(subj_mask, ones(13,13,13)); % Dilate the mask to compensate for the previous erosion in head_mask_mprage;
V_aux = spm_vol(deblank(P(1, :)));
Ims = spm_read_vols(V_aux);
II = find(mm == 0);
Ims(II) = NaN; % Let's make the outside NaN to avoid segmentation there!
aux = spm_write_vol(V_aux, Ims); % Re-save the MPRAGE*normalized image with the mask applied!
pseudo_CT_output('SUCCESS', stage_context, 'Alignment and masking completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now load, modify (with the new files) and run the NEW SEGMENT batch:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Legacy output: disp('Starting the New Segment process (be patient!!) ...');
stage_started = tic;
stage_context = local_stage_context(output_context, 4);
pseudo_CT_output('INFO', stage_context, 'Running SPM New Segment.');
load(fullfile(dir_batch_templates, 'new_segment_batch.mat')); % A new variable called matlabbatch is created!
% We need to change the channels according to the loaded files:
matlabbatch{1}.spm.tools.preproc8.channel(1).vols = {deblank(P(1, :))};
%%%matlabbatch{1}.spm.tools.preproc8.channel(1).biasreg = 0; % Bias regularization to No correction; Not in use anymore
matlabbatch{1}.spm.tools.preproc8.warp.affreg = ''; % This option should be here only if there is an Affine coreg into the MNI before (in move_image_2_MNI.m);
matlabbatch{1}.spm.tools.preproc8.channel(1).biasfwhm = 30; % FWHM to 30mm;
matlabbatch{1}.spm.tools.preproc8.warp.reg = 10; % Warping regularization to 10;
for ii=2:nf
    matlabbatch{1}.spm.tools.preproc8.channel(ii) = matlabbatch{1}.spm.tools.preproc8.channel(1);
    matlabbatch{1}.spm.tools.preproc8.channel(ii).vols = {deblank(P(ii, :))};
end
% Let's include the right path to the template TPM.nii files:
for ii=1:6
    if isdeployed
        matlabbatch{1}.spm.tools.preproc8.tissue(ii).tpm = {strcat(fullfile(dir_batch_templates, 'TPM.nii,'),num2str(ii))};
    else
        matlabbatch{1}.spm.tools.preproc8.tissue(ii).tpm = {strcat(fullfile(spm('Dir'),'toolbox', 'Seg','TPM.nii,'),num2str(ii))};
    end
end
% Let's save it into a new batch file to run it:
fns_seg_batch = strcat(paths, filesep, 'new_segment_', date, '_batch.mat');
save(fns_seg_batch, 'matlabbatch');
clear matlabbatch;
% Legacy output: disp(sprintf('\n\nThe Segmentation step may take 20 to 30 minutes, depending on your computer ... Please be patient!!'));
% Run the New Segment batch just created!:
if ~isdeployed
    evalc('cfg_util(''run'', fns_seg_batch);');
else
    if ispc
        exe_cmd = strcat('!', fullfile(config.spm_root, 'spm8.exe'));
    elseif ismac
        exe_cmd = strcat('!', fullfile(config.spm_root, 'spm8.app/Contents/MacOS/spm8'));
    elseif isunix
        exe_cmd = strcat('!', fullfile(config.spm_root, 'spm8'));
    else
        % Legacy output: disp('The platform is unkonwn!!');
        error('pseudo_CT:UnsupportedPlatform', 'The current platform is unsupported.');
    end
    cmd=[exe_cmd  ' run ' fns_seg_batch];
    eval([cmd]);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Apply bone reduction when enabled by the selected profile.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if config.bone_enabled
    for ii=1:6
        aux = strcat(paths, filesep, 'rc', num2str(ii), fns, exts);
        %copyfile(aux, strcat(paths, filesep, 'rc', num2str(ii), fns, '_orig', exts))
        Prc_old(ii, 1:length(aux)) = aux;
    end
    [Prc_new] = reduce_bone_segment(Prc_old);
end
exten = '';
pseudo_CT_output('SUCCESS', stage_context, 'Segmentation completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Once finished, we need to run the DARTEL EXISTING TEMPLATE batch:
% We will use the newly generated files from the New Segment process run
% just above! (rc1*.nii, where * is the P(1, :) file!);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Legacy output: disp(sprintf('\nStarting the Dartel coregistration process (be patient again!!) ...'));
stage_started = tic;
stage_context = local_stage_context(output_context, 5);
pseudo_CT_output('INFO', stage_context, 'Registering atlases with DARTEL.');
load(fullfile(dir_batch_templates, 'dartel_existing_template_batch.mat')); % A new variable called matlabbatch is created!
% Let's replace the files again:
for ii=1:6
    matlabbatch{1}.spm.tools.dartel.warp1.images{ii} = {strcat(paths, filesep, 'rc', num2str(ii), fns, exten, exts)};
    %matlabbatch{1}.spm.tools.dartel.warp1.images{ii} = {deblank(Prc_new(ii, :))};
end
% Let's include the right path to the Large FOV templates:
for ii=1:6
    tmp_aux = strcat('Template_', num2str(ii), '.nii');
    matlabbatch{1}.spm.tools.dartel.warp1.settings.param(ii).template = {fullfile(dir_batch_templates, tmp_aux)};
end
% Save it into a new batch file to run it:
fns_dartel_exist_template_batch = strcat(paths, filesep, 'dartel_existing_template_', date, '_batch.mat');
save(fns_dartel_exist_template_batch, 'matlabbatch');
clear matlabbatch;
% Run the Dartel Existing Template batch just created!:
%cfg_util('run', fns_dartel_exist_template_batch);
% Legacy output: disp(sprintf('\n\nThe Coreg step may take 5 minutes to run, depending on your computer ... Please be patient!!'));
if ~isdeployed
    evalc('cfg_util(''run'', fns_dartel_exist_template_batch);');
else
    cmd=[exe_cmd  ' run ' fns_dartel_exist_template_batch];
    eval([cmd]);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Once finished, just need to run the INVERSE WARPED batch to create the atlases
% back into subject space:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Legacy output: disp(sprintf('\nStarting the Inverse Warped process (to create the atlases in subject space!) ...'));
pseudo_CT_output('INFO', stage_context, '    Applying inverse warp.');
load(fullfile(dir_batch_templates, 'create_inverse_warped_batch.mat'));
% Let's modify the flow-field field:
matlabbatch{1}.spm.tools.dartel.crt_iwarped.flowfields = {strcat(paths, filesep, 'u_rc1', fns, exten, exts)};
% Now we need to change the Atlases that will be warped into subject space:
for ii=1:length(list_atlas)
    matlabbatch{1}.spm.tools.dartel.crt_iwarped.images{ii} = fullfile(dir_batch_templates, list_atlas(ii).name);
end
% Save it into a new batch file to run it:
fns_create_inverse_warped_batch = strcat(paths, filesep, 'create_inverse_warped_', date, '_batch.mat');
save(fns_create_inverse_warped_batch, 'matlabbatch');
% Run the Create Inverse Warped batch just created!:
%cfg_util('run', fns_create_inverse_warped_batch);
if ~isdeployed
    evalc('cfg_util(''run'', fns_create_inverse_warped_batch);');
else
    cmd=[exe_cmd  ' run ' fns_create_inverse_warped_batch];
    eval([cmd]);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Once finished, there should be 5 new files (from the 5 Atlases: CT,
% MPRAGE, UTE_1, UTE_2 and head_mask! RESLICE the new atlas into subject
% space
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Legacy output: disp(sprintf('\nStarting the final reslicing of the atlas in real subject space (which is Image:\n%s)', deblank(P(1, :))));
pseudo_CT_output('INFO', stage_context, '    Reslicing atlases into MPRAGE space.');
num_atlas = length(matlabbatch{1}.spm.tools.dartel.crt_iwarped.images); % Number of warped atlas just created
clear Pr;
Pr(1, :) = deblank(P(1, :));
for ii=1:num_atlas
    [pathw,fnw,extw] = fileparts(matlabbatch{1}.spm.tools.dartel.crt_iwarped.images{ii});
    aux = strcat(paths, filesep,'w', fnw, '_', 'u_rc1', fns, exten, extw);
    Pr((ii+1), 1:length(aux)) = aux; % Just in case the new name is longer than the matrix Pr!
end
% Let's reslice them back into MPRAGE space (P(1, :)):
spm_reslice(Pr, flg); % Reslice only!


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Finished! Just display the final files created!!:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Legacy output: disp(sprintf('\nCoregistration and reslicing finished!!!!'));
% Legacy output: disp('Files created:');
for ii=1:num_atlas
    [pathf,fnf,extf] = fileparts(deblank(Pr(ii+1, :)));
    aux = strcat(pathf, filesep,'r', fnf, extf);
    Pf(ii, 1:length(aux)) = aux; % Just in case the new name is longer than the matrix P!
    % Legacy output: disp(sprintf('%s\n', aux));
end
pseudo_CT_output('SUCCESS', stage_context, 'Atlas registration completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Finally, we just need to convert the CT atlas into an attenuation map and
% multiply by the head_mask to get a clean attenuation map!
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Legacy output: disp(sprintf('\nCreating att_map file ...'));
stage_started = tic;
stage_context = local_stage_context(output_context, 6);
pseudo_CT_output('INFO', stage_context, 'Building attenuation map and QC image.');
% First look for th CT file within Pf:
for ii=1:num_atlas
    st_f = strfind(deblank(Pf(ii,:)), 'Atlas_rCT');
    if length(st_f) > 0
        pos_CT = ii;
        break;
    end
end
V_CT = spm_vol(Pf(pos_CT, :));
CT = spm_read_vols(V_CT);
[att_map] = CT_2_att_map(CT);

% Now, let's multiply it by the head_mask:
for ii=1:num_atlas
    st_f = strfind(deblank(Pf(ii,:)), 'Atlas_head_mask');
    if length(st_f) > 0
        pos_mask = ii;
        break;
    end
end
V_mask = spm_vol(Pf(pos_mask, :));
mask = spm_read_vols(V_mask);
att_map = att_map.*mask;

% Now let's save the attenuation map in the same space:
fn_att_map = fullfile(paths, 'att_map_no_filled.nii');
V_att_map = V_CT;
V_att_map.fname = fn_att_map;
V_att_map.dt = [16 0]; % To save it as float32;

% Let's change the .mat to match the original MPRAGE image:
V_orig = spm_vol(deblank(P_orig(1, :)));
V_att_map.mat = V_orig.mat;
%aux = spm_write_vol(V_att_map, att_map);

% Let's get Original MPRAGE mask and then let's make whatever is not
% covered by the atlas mask become soft-tissue:
orig_mprage = spm_read_vols(V_orig);
[aux, subj_mask] = head_mask_mprage(orig_mprage, 20); % It used to be 30 up to version 1.5 included;
% For version 1.7: Choose only the biggest blob in the mask!
[L, num] = bwlabeln(subj_mask);
if num > 1
    for ii=1:num
        aux = L == ii;
        suma(ii) = sum(aux(:));
    end
    [Y, pos_max] = max(suma);
    subj_mask = L == pos_max;
end

I = find((subj_mask-mask) == 1); % Only those voxels where subj_mask exists but not mask!
att_map(I) = 0.096; % Make those voxels to be Soft-tissue = 0.096;
% Version 1.6.1: Once I have filled the gaps (as in version 1.5) then get the outter part
% of the extended mask and assign those to 0.096 if they are ok in MPRAGE!
subj_mask_dil = imdilate(subj_mask, ones(7,7,7));
subj_mask_eroded = imerode(subj_mask, ones(13,13,13)); % For version 1.6;
diff = (subj_mask_dil - subj_mask_eroded).* (att_map < 0.08).* (orig_mprage > 20); % For version 1.6
I = find(diff); att_map(I) = 0.096;
% Optionally multiply by the subject mask. The selected profile owns this
% compatibility policy.
if strcmp(config.zero_background, 'Yes')
    att_map = att_map.*((subj_mask_dil + (orig_mprage > 20)) > 0);
end
% Rename the filename to save it!
fn_att_map = fullfile(paths, 'att_map.nii');
V_att_map.fname = fn_att_map;

% Let's write the file:
aux = spm_write_vol(V_att_map, att_map);

% Add the attenuation map file to the list to be returned:
Pf(num_atlas+1, 1:length(fn_att_map)) = fn_att_map;
% Legacy output: disp(sprintf('Attenuation map file created:\n%s\n', deblank(Pf(num_atlas+1, :))));

% Jun/25/2016: Printing a validation image:
%ss = strfind(paths, filesep);
%pat_folder = paths(1:ss(end)-1);
%pat_folder = home_dir(paths);
composite = quick_fusion_pseudo_ct(paths);
imwrite(composite, fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'Resolution', 300);

try
    close(fh);
catch
end
% Legacy output: disp('Whole process finished!!!!');

% Write Pseudo_CT_AC_Version.txt with changelog content
status = pseudo_CT_write_version_log(code_version, paths, stage_context);
if status ~= 1
    % Legacy output: disp('WARNING: Pseudo_CT_AC_Version.txt was written in fallback mode — CHANGELOG.md could not be copied.');
    pseudo_CT_output('WARN', stage_context, ...
        'Version log used fallback content because CHANGELOG.md could not be copied.');
end
pseudo_CT_output('SUCCESS', stage_context, ...
    'Attenuation map and QC completed (elapsed %s).', local_elapsed(toc(stage_started)));


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
