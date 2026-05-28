function run_pseudo_CT_local(varargin)
%RUN_PSEUDO_CT_LOCAL Run the editable pseudo-CT pipeline locally.
%   RUN_PSEUDO_CT_LOCAL() opens the existing single-subject GUI, lets the
%   user select the required MR files, and runs the local MATLAB/SPM
%   pseudo-CT pipeline for one subject.
%
%   RUN_PSEUDO_CT_LOCAL('batch') opens a multi-select file picker for
%   MPRAGE files and processes each selected subject sequentially.
%
%   RUN_PSEUDO_CT_LOCAL(SUBJECT_LIST) processes an explicit list of MPRAGE
%   files. SUBJECT_LIST can be:
%       - a single MPRAGE filename
%       - a char matrix with one filename per row
%       - a cell array of filenames
%
%   RUN_PSEUDO_CT_LOCAL(..., CORRECT_ALIASING) overrides the anti-aliasing
%   flag used by the local pipeline. CORRECT_ALIASING should be numeric or
%   logical: use 1/true to enable the correction and 0/false to disable it.
%   When omitted, batch and explicit-list execution default to 1. In GUI
%   mode, the value returned by LOAD_MR_4_AC is used.
%
%   Batch and explicit-list execution auto-discover the subject UMAP
%   reference from the subject folder layout. Subjects without a detected
%   UMAP are skipped.
%
%   Examples:
%       run_pseudo_CT_local('batch')
%       run_pseudo_CT_local('batch', 0)
%       subject_list = {
%           '/path/to/subj1/MR/MEMPRAGE/file1.IMA'
%           '/path/to/subj2/MR/MEMPRAGE/file1.IMA'
%       };
%       run_pseudo_CT_local(subject_list)
%       run_pseudo_CT_local(subject_list, 0)
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

% if isdeployed
%     if nargin == 1
%         load(varargin{1}); % Load variable defaults!
%     else
%         disp('The Deployed application requires the defaults *.mat!!');
%         return;
%     end
%     if ~generate_key_number_for_pseudo_ct_deployed_package(defaults.key_number)
%         disp('The key_number field on the defaults_pseudo_CT is NOT valid!\nPlease enter a valid one or email davidizq@nmr.mgh.harvard.edu for one!');
%         return;
%     end
% end

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

% Get where the Templates are:
dir_batch_templates = fullfile(pathp, 'Batch_atlas');
% if isdeployed
%     dir_batch_templates = fullfile(defaults.deployed_folder, 'Batch_atlas');
% end

jobs = local_collect_jobs(varargin{:});
if isempty(jobs)
    warning(orig_warn);
    return;
end

num_success = 0;
num_failed = 0;
show_subject_dialog = length(jobs) == 1;
for jj=1:length(jobs)
    if length(jobs) > 1
        disp(sprintf('\nStarting local pseudo-CT subject %d of %d:\n%s\n', jj, length(jobs), jobs(jj).mprage_fn));
    end
    if local_run_subject(jobs(jj), dir_batch_templates, defaults, orig_warn, show_subject_dialog)
        num_success = num_success + 1;
    else
        num_failed = num_failed + 1;
    end
end

warning(orig_warn);

if ~isdeployed && length(jobs) > 1
    disp(sprintf('\nLocal pseudo-CT batch finished. Success: %d  Failed: %d\n', num_success, num_failed));
end

return

function jobs = local_collect_jobs(varargin)

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
        jobs = local_build_jobs_from_subject_list(subject_list, correct_aliasing);
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

function jobs = local_build_jobs_from_subject_list(subject_list, correct_aliasing)

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

function success = local_run_subject(job, dir_batch_templates, defaults, orig_warn, show_dialog)

success = 0;

[pathr, fnr, extr] = fileparts(deblank(job.mprage_fn)); %#ok<ASGLU>
[processing_dir, temp_dir, save_dir] = pseudo_CT_resolve_output_dirs(pathr);
dir_list = {processing_dir, temp_dir, save_dir};
for ii=1:length(dir_list)
    if exist(dir_list{ii}, 'dir') ~= 7
        [mkdir_success, msg] = mkdir(dir_list{ii});
        if mkdir_success == 0
            disp(sprintf('There was an error creating the directory %s\n%s', dir_list{ii}, msg));
            return;
        end
    end
end

% If all images are ok then continue:
HOSTNAME = defaults_pseudo_CT('HOSTNAME'); % Address of Launchpad computer!
% if isdeployed
%     HOSTNAME = defaults.HOSTNAME;
% end
if strcmp(HOSTNAME, '127.0.0.1') || strcmpi(HOSTNAME, 'localhost')
    USERNAME = getenv('USER');
    if isempty(USERNAME)
        USERNAME = getenv('LOGNAME');
    end
    if isempty(USERNAME)
        USERNAME = 'local';
    end
    ssh_log = struct('username', USERNAME, 'password', '', 'hostname', HOSTNAME, 'autoreconnect', 0);
else
    [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
        'WindowName', sprintf('Login for: %s', HOSTNAME));
    ssh_log = struct('username', USERNAME, 'password', PASSWORD, 'hostname', HOSTNAME, 'autoreconnect', 0);
end

clear USERNAME PASSWORD HOSTNAME

P = convert_dicom_i_2_nii(job.mprage_fn, 'mprage.nii', temp_dir); % To convert the MPRAGE files into a *.nii

[temp_working_dir, fnr, extr] = fileparts(deblank(P)); %#ok<ASGLU>
disp(sprintf('\n\nThis is the temporary working directory where intermediate results will be saved:\n%s\n', temp_working_dir));

% For the reference image (4th input argument):
[Pf] = atlas_based_attenuation_map(P, dir_batch_templates, ssh_log, job.correct_aliasing, defaults); % Run the pseudo-ct code!
if ~ischar(Pf) || isempty(strtrim(Pf))
    disp('Pseudo-CT processing stopped before generating atlas outputs.');
    return;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now convert the att_map.nii into Dicom (using Spencer's code):
% define constants
FWHM    = 0; % In mm, the FWHM of the Gaussian filter to apply before registration! % Used to be 4mm (before May/3/2017)
[temp_working_dir, fnr, extr] = fileparts(deblank(Pf(end, :))); %#ok<ASGLU>
try
    pseudo_CT_write_mu_map_dicom(fullfile(temp_working_dir, 'att_map.nii'), save_dir, job.umap_fn, temp_dir, FWHM);
catch ME
    disp(ME.message);
    return;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%% Clean the folder! %%%%%%
button = 'Yes'; % By default, erase all the intermediate files!
promotion_success = pseudo_CT_promote_final_outputs(temp_working_dir, processing_dir, P);
if ~promotion_success
    disp(sprintf('Final pseudo-CT files were left in the temporary folder:\n%s\n', temp_working_dir));
elseif strcmp(button, 'Yes')
    [remove_success, msg] = rmdir(temp_working_dir, 's');
    if remove_success == 0
        disp(sprintf('There was an error removing the temporary directory %s\n%s', temp_working_dir, msg));
    end
end

disp(sprintf('\n\nYour att-map Dicom images have been saved in:\n%s\n', save_dir));
if promotion_success
    disp(sprintf('The final pseudo-CT NIfTI/QC files were saved in:\n%s\n', processing_dir));
end

if show_dialog && ~isdeployed
    warndlg('Pseudo-CT image finished!!', 'Pseudo-CT finished!!');
end

success = 1;

return