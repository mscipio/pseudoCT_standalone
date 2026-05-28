function run_pseudo_CT_launchpad(varargin)
%RUN_PSEUDO_CT_LAUNCHPAD Run the legacy compiled pseudo-CT backend.
%   RUN_PSEUDO_CT_LAUNCHPAD() opens the existing single-subject GUI, lets
%   the user select the required MR files, prompts for Launchpad
%   credentials, stages the subject under MR_PET/tmp, submits the legacy
%   compiled Launchpad pseudo-CT workflow, then writes the final DICOM
%   pseudo-muMAP locally.
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

defaults = '';

if isdeployed
    if nargin == 1
        load(varargin{1}); % Load variable defaults!
    end
end

orig_warn = warning;
warning('off', 'all');

[pathp, ~, ~] = fileparts(mfilename('fullpath'));
addpath(pathp, '-begin');
if exist(fullfile(pathp, 'src'), 'dir') == 7
    addpath(genpath(fullfile(pathp, 'src')), '-begin');
end
if exist(fullfile(pathp, 'spm8-r6313'), 'dir') == 7
    addpath(genpath(fullfile(pathp, 'spm8-r6313')), '-begin');
end
if exist(fullfile(pathp, 'imgaussian'), 'dir') == 7
    addpath(genpath(fullfile(pathp, 'imgaussian')), '-begin');
end
if exist(fullfile(pathp, 'ssh2_v2_m1_r5'), 'dir') == 7
    addpath(genpath(fullfile(pathp, 'ssh2_v2_m1_r5')), '-begin');
end
if exist(fullfile(pathp, 'vers'), 'dir') == 7
    addpath(fullfile(pathp, 'vers'), '-begin');
end
clear spm_vol_nifti spm_preproc_write8
rehash;

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
            if success == 0
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

[ssh2_conn, jobname, rand_fold, ss_tot] = batch_pseudo_CT_launchpad(P, ssh_log, 'clean_folder', 0, 'check_aliasing', jobs(1).correct_aliasing); %#ok<ASGLU>

num_success = 0;
num_failed = 0;
button = 'Yes';
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
        pseudo_CT_write_mu_map_dicom(fullfile(jobs(jj).temp_dir, 'att_map.nii'), jobs(jj).save_dir, jobs(jj).umap_fn, jobs(jj).temp_dir, 0);
    catch ME
        disp(ME.message);
        num_failed = num_failed + 1;
        continue;
    end

    promotion_success = pseudo_CT_promote_final_outputs(jobs(jj).temp_dir, jobs(jj).processing_dir, deblank(P(jj, :)));
    if ~promotion_success
        disp(sprintf('Final pseudo-CT files were left in the temporary folder:\n%s\n', jobs(jj).temp_dir));
    elseif strcmp(button, 'Yes')
        [remove_success, msg] = rmdir(jobs(jj).temp_dir, 's');
        if remove_success == 0
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
if ~isstr(mprage_fn) | ~isstr(ute_fn) | ~isstr(umap_fn)
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