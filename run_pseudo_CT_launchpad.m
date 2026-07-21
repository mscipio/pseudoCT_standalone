function run_pseudo_CT_launchpad(varargin)
%RUN_PSEUDO_CT_LAUNCHPAD Run the legacy compiled pseudo-CT backend.
%   RUN_PSEUDO_CT_LAUNCHPAD() opens the existing single-subject GUI, lets
%   the user select the required MR files, prompts for Launchpad
%   credentials, stages the subject under MR_PET/tmp, submits the legacy
%   compiled Launchpad pseudo-CT workflow, then writes the final DICOM
%   pseudo-muMAP locally.
%
%   Minimum supported MATLAB: R2010b (7.11).  Modern MATLAB (R2013b+)
%   MAY produce divergent optimizer results.
%
%   RUN_PSEUDO_CT_LAUNCHPAD('batch') opens a multi-select file picker for
%   MPRAGE files, submits all selected subjects through the Launchpad
%   backend, then finalizes each successful subject locally.
%
%   RUN_PSEUDO_CT_LAUNCHPAD(SUBJECT_LIST) processes an explicit list of
%   MPRAGE files. SUBJECT_LIST can be:
%       - a single MPRAGE filename
%       - a char matrix with one filename per row
%       - a cell array of filenames
%
%   RUN_PSEUDO_CT_LAUNCHPAD(..., CORRECT_ALIASING) overrides the
%   anti-aliasing flag sent to the Launchpad backend for batch or explicit
%   list execution. CORRECT_ALIASING should be numeric or logical: use
%   1/true to enable the correction and 0/false to disable it. When
%   omitted, batch and explicit-list execution default to 1. In GUI mode,
%   the value returned by LOAD_MR_4_AC is used.
%
%   Batch and explicit-list execution auto-discover the subject UMAP
%   reference from the subject folder layout. Subjects without a detected
%   UMAP are skipped. Launchpad credentials are requested once and reused
%   for the full batch.
%
%   Examples:
%       run_pseudo_CT_launchpad('batch')
%       run_pseudo_CT_launchpad('batch', 0)
%       subject_list = {
%           '/path/to/subj1/MR/MEMPRAGE/file1.IMA'
%           '/path/to/subj2/MR/MEMPRAGE/file1.IMA'
%       };
%       run_pseudo_CT_launchpad(subject_list)
%       run_pseudo_CT_launchpad(subject_list, 0)
%
%   RUN_PSEUDO_CT_LAUNCHPAD(DEFAULTS_MAT) is supported only in deployed
%   mode. DEFAULTS_MAT should point to a MAT file containing the defaults
%   structure expected by the compiled application.
%
%   Outputs:
%       - final DICOM pseudo-muMAP images are written to MR/pseudo_muMAP
%       - final NIfTI/QC/version files are written to MR_PET
%       - intermediate files are staged in MR_PET/tmp and removed on
%         successful completion
%
%   Maintained by Michele Scipioni, PhD
%   mscipioni@mgh.harvard.edu
%   Updated: May 28, 2026.
%   Minimum supported MATLAB: R2010b (matches cluster's compiled-app runtime, MCR 7.11)

defaults = '';

if isdeployed
    if nargin == 1
        load(varargin{1}); % Load variable defaults!
    end
end

orig_warn = warning;
warning('off', 'all');

[pathp, ~, ~] = fileparts(mfilename('fullpath'));
addpath(fullfile(pathp, 'src', 'config'), '-begin');
setup_pseudo_CT_paths(pathp);

jobs = launchpad_collect_jobs(varargin{:});
if isempty(jobs)
    warning(orig_warn);
    return;
end

P = '';
for ii=1:length(jobs)
    [pathr, fnr, extr] = fileparts(deblank(jobs(ii).mprage_fn)); %#ok<ASGLU>
    [processing_dir, temp_dir, save_dir] = pseudo_CT_resolve_output_dirs(pathr);
    jobs(ii).processing_dir = processing_dir;
    jobs(ii).temp_dir = temp_dir;
    jobs(ii).save_dir = save_dir;

    dir_list = {processing_dir, temp_dir, save_dir};
    for kk=1:length(dir_list)
        if exist(dir_list{kk}, 'dir') ~= 7
            [success, msg] = mkdir(dir_list{kk});
            if ~success
                warning(orig_warn);
                disp(sprintf('There was an error creating the directory %s\n%s', dir_list{kk}, msg));
                return;
            end
        end
    end

    if length(jobs) > 1
        disp(sprintf('\nPreparing Launchpad pseudo-CT subject %d of %d:\n%s\n', ii, length(jobs), jobs(ii).mprage_fn));
    end
    jobs(ii).seed_nii = convert_dicom_i_2_nii(jobs(ii).mprage_fn, 'mprage.nii', temp_dir);
    P(ii, 1:length(jobs(ii).seed_nii)) = jobs(ii).seed_nii;
    disp(sprintf('\n\nThis is the temporary working directory where intermediate results will be saved:\n%s\n', temp_dir));
end

HOSTNAME = defaults_pseudo_CT_launchpad('HOSTNAME');
if isdeployed && isstruct(defaults) && isfield(defaults, 'HOSTNAME')
    HOSTNAME = defaults.HOSTNAME;
end
[PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
    'WindowName', sprintf('Login for: %s', HOSTNAME));
ssh_log = {USERNAME, PASSWORD, HOSTNAME};
clear USERNAME PASSWORD HOSTNAME

keep_temp = pseudo_CT_keep_temp_enabled(@defaults_pseudo_CT_launchpad);
zero_background_defaults = @defaults_pseudo_CT_launchpad;
if isdeployed && isstruct(defaults)
    zero_background_defaults = @(defstr) defaults.(defstr);
end
zero_background = pseudo_CT_zero_background_enabled(zero_background_defaults);
keep_tmp_val = 0;
if strcmp(keep_temp, 'Yes')
    keep_tmp_val = 1;
end
[ssh2_conn, jobname, rand_fold, ss_tot] = batch_pseudo_CT_launchpad(P, ssh_log, 'clean_folder', 0, 'keep_tmp', keep_tmp_val, 'check_aliasing', jobs(1).correct_aliasing); %#ok<ASGLU>

num_success = 0;
num_failed = 0;
should_cleanup = true;  % default: remove intermediate temp files
if strcmp(keep_temp, 'Yes')
    should_cleanup = false;  % operator requested preservation
end
for jj=1:length(jobs)
    if ss_tot(jj) ~= 0
        disp(sprintf('Pseudo-CT Launchpad processing failed for:\n%s\n', jobs(jj).mprage_fn));
        num_failed = num_failed + 1;
        continue;
    end

    if length(jobs) > 1
        disp(sprintf('\nFinalizing Launchpad pseudo-CT subject %d of %d:\n%s\n', jj, length(jobs), jobs(jj).mprage_fn));
    end

    try
        if strcmp(zero_background, 'Yes')
            launchpad_apply_background_mask(jobs(jj).temp_dir);
        end
        pseudo_CT_write_mu_map_dicom(fullfile(jobs(jj).temp_dir, 'att_map.nii'), jobs(jj).save_dir, jobs(jj).umap_fn, jobs(jj).temp_dir, 0);
    catch ME
        fprintf(1, '[launchpad-debug] Failed to write mu-map DICOM for subject:\n%s\n', jobs(jj).mprage_fn);
        tmp_list = dir(jobs(jj).temp_dir);
        if ~isempty(tmp_list)
            tmp_names = {tmp_list(~ismember({tmp_list.name}, {'.', '..'})).name};
            if ~isempty(tmp_names)
                tmp_str = '';
                for ti = 1:length(tmp_names)
                    if ti > 1
                        tmp_str = [tmp_str ', ']; %#ok<AGROW>
                    end
                    tmp_str = [tmp_str tmp_names{ti}]; %#ok<AGROW>
                end
                fprintf(1, '[launchpad-debug] temp_dir (%s) contents: %s\n', jobs(jj).temp_dir, tmp_str);
            end
        end
        disp(ME.message);
        num_failed = num_failed + 1;
        continue;
    end

    promotion_success = pseudo_CT_promote_final_outputs(jobs(jj).temp_dir, jobs(jj).processing_dir, deblank(P(jj, :)));
    if ~promotion_success
        disp(sprintf('Final pseudo-CT files were left in the temporary folder:\n%s\n', jobs(jj).temp_dir));
    elseif should_cleanup
        [remove_success, msg] = rmdir(jobs(jj).temp_dir, 's');
        if ~remove_success
            disp(sprintf('There was an error removing the temporary directory %s\n%s', jobs(jj).temp_dir, msg));
        end
    end

    disp(sprintf('\n\nYour att-map Dicom images have been saved in:\n%s\n', jobs(jj).save_dir));
    if promotion_success
        disp(sprintf('The final pseudo-CT NIfTI/QC files were saved in:\n%s\n', jobs(jj).processing_dir));
    end
    num_success = num_success + 1;
end

warning(orig_warn);

if ~isdeployed && length(jobs) > 1
    disp(sprintf('\nLaunchpad pseudo-CT batch finished. Success: %d  Failed: %d\n', num_success, num_failed));
end

if ~isdeployed && length(jobs) == 1
    warndlg('Pseudo-CT image finished!!', 'Pseudo-CT finished!!');
end

return

function launchpad_apply_background_mask(temp_dir)

att_map_path = fullfile(temp_dir, 'att_map.nii');
normalized_path = fullfile(temp_dir, 'mprage_normalized.nii');
if exist(normalized_path, 'file') ~= 2
    fprintf(1, ['WARNING: zero_background was requested, but %s is missing.\n', ...
                'The fetched Launchpad attenuation map will remain unmasked.\n'], normalized_path);
    return;
end

try
    V_att_map = spm_vol(att_map_path);
    att_map = spm_read_vols(V_att_map);
    V_orig = spm_vol(normalized_path);
    orig_mprage = spm_read_vols(V_orig);
    if ~isequal(size(att_map), size(orig_mprage))
        fprintf(1, ['WARNING: zero_background could not be applied because att_map.nii ', ...
                    'and mprage_normalized.nii have different dimensions.\n', ...
                    'The fetched Launchpad attenuation map will remain unmasked.\n']);
        return;
    end

    [~, subj_mask] = head_mask_mprage(orig_mprage, 20);
    [L, num] = bwlabeln(subj_mask);
    if num > 1
        component_sizes = zeros(1, num);
        for ii=1:num
            component_sizes(ii) = sum(L(:) == ii);
        end
        [~, pos_max] = max(component_sizes);
        subj_mask = L == pos_max;
    end
    subj_mask_dil = imdilate(subj_mask, ones(7,7,7));
    att_map = att_map.*((subj_mask_dil + (orig_mprage > 20)) > 0);
    spm_write_vol(V_att_map, att_map);
catch ME_mask
    fprintf(1, ['WARNING: zero_background could not be applied: %s\n', ...
                'The fetched Launchpad attenuation map will remain unmasked.\n'], ME_mask.message);
end

return

function jobs = launchpad_collect_jobs(varargin)

jobs = struct('mprage_fn', {}, 'umap_fn', {}, 'correct_aliasing', {});

if ~isdeployed && nargin > 0
    subject_list = '';
    if ischar(varargin{1}) && strcmpi(strtrim(varargin{1}), 'batch')
        subject_list = spm_select(Inf, '*', 'Select the MPRAGE files to use to obtain atlas-based attenuation maps');
    elseif iscell(varargin{1})
        subject_list = char(varargin{1});
    elseif ischar(varargin{1}) && size(varargin{1}, 1) > 1
        subject_list = varargin{1};
    elseif ischar(varargin{1}) && exist(strtrim(varargin{1}), 'file') == 2
        subject_list = char(varargin{1});
    end

    if ~isempty(subject_list)
        correct_aliasing = 1;
        if nargin > 1 && (isnumeric(varargin{2}) || islogical(varargin{2}))
            correct_aliasing = varargin{2};
        end
        jobs = launchpad_build_jobs_from_subject_list(subject_list, correct_aliasing);
        return;
    end
end

[mprage_fn, ute_fn, umap_fn, correct_aliasing] = load_mr_4_AC('mMR');

if mprage_fn == 0
    return;
end
if ~ischar(mprage_fn) || ~ischar(ute_fn) || ~ischar(umap_fn)
    warndlg('There are some of the filenames missing', 'Files missing!');
    return
end

jobs(1).mprage_fn = mprage_fn;
jobs(1).umap_fn = umap_fn;
jobs(1).correct_aliasing = correct_aliasing;

return

function jobs = launchpad_build_jobs_from_subject_list(subject_list, correct_aliasing)

jobs = struct('mprage_fn', {}, 'umap_fn', {}, 'correct_aliasing', {});

if ischar(subject_list) && isrow(subject_list)
    subject_list = char(subject_list);
end

kk = 0;
for ii=1:size(subject_list, 1)
    mprage_fn = strtrim(subject_list(ii, :));
    if isempty(mprage_fn)
        continue;
    end
    [ute_fn, umap_fn] = pseudo_CT_auto_discover_ute_umap(mprage_fn); %#ok<NASGU>
    if ~ischar(umap_fn) || exist(umap_fn, 'file') ~= 2
        disp(sprintf('Skipping subject because no UMAP reference was found:\n%s\n', mprage_fn));
        continue;
    end
    kk = kk + 1;
    jobs(kk).mprage_fn = mprage_fn;
    jobs(kk).umap_fn = umap_fn;
    jobs(kk).correct_aliasing = correct_aliasing;
end

return
