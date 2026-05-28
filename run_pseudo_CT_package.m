% Date: Sept/18/2014;
% Name: run_pseudo_CT_package.m;
% Function to run the pseudo-CT package to create a pseudo-CT image from an
% MPRAGE image (MRI).
%
% To run it, just type: run_pseudo_CT_package  
% on the matlab prompt and then follow the instructions on the screen;

function run_pseudo_CT_package(varargin)

defaults = '';

if isdeployed
    if nargin == 1
        load(varargin{1}); % Load variable defaults!
    else
        disp('The Deployed application requires the defaults *.mat!!');
        return;
    end
    if ~generate_key_number_for_pseudo_ct_deployed_package(defaults.key_number)
        disp('The key_number field on the defaults_pseudo_CT is NOT valid!\nPlease enter a valid one or email davidizq@nmr.mgh.harvard.edu for one!');
        return;
    end
end

orig_warn = warning;
warning('off', 'all');

[pathp, ~, ~] = fileparts(mfilename('fullpath'));
addpath(pathp, '-begin');
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

[mprage_fn, ute_fn, umap_fn, correct_aliasing] = load_mr_4_AC('mMR');

if mprage_fn == 0
    return;
end
if ~isstr(mprage_fn) | ~isstr(ute_fn) | ~isstr(umap_fn)
    warndlg('There are some of the filenames missing', 'Files missing!');
    return
end

[pathr, fnr, extr] = fileparts(deblank(mprage_fn));
[working_dir, temp_dir, save_dir] = local_resolve_output_dirs(pathr);
dir_list = {working_dir, temp_dir, save_dir};
for ii=1:length(dir_list)
    if exist(dir_list{ii}, 'dir') ~= 7
        [success, msg] = mkdir(dir_list{ii});
        if success == 0
            warning(orig_warn);
            disp(sprintf('There was an error creating the directory %s\n%s', dir_list{ii}, msg));
            return;
        end
    end
end

% Get where the Templates are:
dir_batch_templates = fullfile(pathp, 'Batch_atlas');
if isdeployed
    dir_batch_templates = fullfile(defaults.deployed_folder, 'Batch_atlas');
end

% Add the java path if needed!
if isdir(fullfile(dir_batch_templates, 'ganymed-ssh2-build250'))
    a = javaclasspath;
    if (length(a) == 0) | (length(strfind(a{1}, 'ganymed-ssh2-build250')) == 0)
        javaaddpath(fullfile(dir_batch_templates, 'ganymed-ssh2-build250', 'ganymed-ssh2-build250.jar'));
    end
end

% If all images are ok then continue:
HOSTNAME = defaults_pseudo_CT('HOSTNAME'); % Address of Launchpad computer!
if isdeployed
    HOSTNAME = defaults.HOSTNAME;
end
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

P = convert_dicom_i_2_nii(mprage_fn, 'mprage.nii', working_dir); % To convert the MPRAGE files into a *.nii

[working_dir, fnr, extr] = fileparts(deblank(P));
disp(sprintf('\n\nThis is the working directory were all the results will be saved:\n%s\n', working_dir));

% For the reference image (4th input argument):
[Pf] = atlas_based_attenuation_map(P, dir_batch_templates, ssh_log, correct_aliasing, defaults); % Run the pseudo-ct code!
if ~ischar(Pf) || isempty(strtrim(Pf))
    warning(orig_warn);
    disp('Pseudo-CT processing stopped before generating atlas outputs.');
    return;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now convert the att_map.nii into Dicom (using Spencer's code):
% define constants
FWHM    = 0; % In mm, the FWHM of the Gaussian filter to apply before registration! % Used to be 4mm (before May/3/2017)
interp_f = 1;
scale_val= 1;
[pathr, fnr, extr] = fileparts(deblank(Pf(end, :)));
if exist(fullfile(pathr, 'att_map.nii'), 'file') ~= 2
    warning(orig_warn);
    disp(sprintf('Pseudo-CT processing finished without creating:\n%s', fullfile(pathr, 'att_map.nii')));
    return;
end

% Run the conversion to Dicom!
mMR_nii2mu_dicom_blur_david(fullfile(pathr, 'att_map.nii'), save_dir, umap_fn, interp_f, scale_val, FWHM, temp_dir);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%% Clean the folder! %%%%%%
current_dir = pwd;
cd(pathr);
button = 'Yes'; % By default, erase all the intermediate files!
switch button
    case 'Yes'
        delete('*ute*', '*UTE*','*Atlas*','*seg8.mat','rp_mu*.i*','new_segment*.mat','create_inverse*.mat','dartel_existing*.mat','*_repos.nii')
    case 'No'
end
cd(current_dir);

warning(orig_warn);

disp(sprintf('\n\nYour att-map Dicom images have been saved in:\n%s\n', save_dir));

if ~isdeployed
    warndlg('Pseudo-CT image finished!!', 'Pseudo-CT finished!!');
end

return

function [processing_dir, temp_dir, save_dir] = local_resolve_output_dirs(series_dir)

mr_dir = '';
search_dir = series_dir;
while ~isempty(search_dir)
    [parent_dir, dir_name] = fileparts(search_dir);
    if strcmpi(dir_name, 'MR')
        mr_dir = search_dir;
        break;
    end
    if strcmp(parent_dir, search_dir)
        break;
    end
    search_dir = parent_dir;
end

if isempty(mr_dir)
    mr_dir = fileparts(series_dir);
    if isempty(mr_dir)
        mr_dir = series_dir;
    end
    subject_root = mr_dir;
else
    subject_root = fileparts(mr_dir);
end

processing_dir = fullfile(subject_root, 'MR_PET');
temp_dir = fullfile(processing_dir, 'tmp');
save_dir = fullfile(mr_dir, 'pseudo_muMAP');