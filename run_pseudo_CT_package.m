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

[mprage_fn, ute_fn, umap_fn, correct_aliasing] = load_mr_4_AC('mMR');

if mprage_fn == 0
    return;
end
if ~isstr(mprage_fn) | ~isstr(ute_fn) | ~isstr(umap_fn)
    warndlg('There are some of the filenames missing', 'Files missing!');
    return
end

[pathr, fnr, extr] = fileparts(deblank(mprage_fn));
str = strfind(pathr, filesep);
working_dir = pathr(1:str(end));

% Get where the Templates are:
[pathp, fnp, extp] = fileparts(mfilename('fullpath'));
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
[PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
    'WindowName', sprintf('Login for: %s', HOSTNAME));
ssh_log = {USERNAME, PASSWORD, HOSTNAME};

clear USERNAME PASSWORD HOSTNAME

P = convert_dicom_i_2_nii(mprage_fn, 'mprage.nii', working_dir); % To convert the MPRAGE files into a *.nii

[working_dir, fnr, extr] = fileparts(deblank(P));
disp(sprintf('\n\nThis is the working directory were all the results will be saved:\n%s\n', working_dir));
save_dir = fullfile(working_dir, 'pseudo_muMAP');
if exist(save_dir) ~= 7
    % Create the directory:
    [success] = mkdir(save_dir);
    if success == 0
        disp(sprintf('There was an error creating the directory %s', save_dir));
        return;
    end
end

% For the reference image (4th input argument):
[Pf] = atlas_based_attenuation_map(P, dir_batch_templates, ssh_log, correct_aliasing, defaults); % Run the pseudo-ct code!

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now convert the att_map.nii into Dicom (using Spencer's code):
% define constants
FWHM    = 0; % In mm, the FWHM of the Gaussian filter to apply before registration! % Used to be 4mm (before May/3/2017)
interp_f = 1;
scale_val= 1;
[pathr, fnr, extr] = fileparts(deblank(Pf(end, :)));

% Run the conversion to Dicom!
mMR_nii2mu_dicom_blur_david(fullfile(pathr, 'att_map.nii'), save_dir, umap_fn, interp_f, scale_val, FWHM);

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