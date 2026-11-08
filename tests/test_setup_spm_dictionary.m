function test_setup_spm_dictionary()
%TEST_SETUP_SPM_DICTIONARY Installed setup joins and verifies the packaged dictionary.
%   Synthetic installed package in scratch only (no SPM, no conversion, no science).
%   Installed setup must reject a missing dictionary before anything else, and must
%   join the packaged resources folder when the dictionary is present. Source mode
%   must not run the check.

repo = fileparts(fileparts(mfilename('fullpath')));
scratch_root = getenv('PSEUDOCT_TEST_SCRATCH');
if isempty(scratch_root)
    scratch_root = tempdir;
end
work = tempname(scratch_root);
mkdir(work);
old_path = path();
old_install = getenv('PSEUDOCT_INSTALL_ROOT');
cleanup = onCleanup(@() local_restore(old_path, old_install)); %#ok<NASGU>
addpath(genpath(fullfile(repo, 'src')), '-begin');

pkg = fullfile(work, 'installed-package');
mkdir(fullfile(pkg, 'runtimes'));
mkdir(fullfile(pkg, 'bin'));
mkdir(fullfile(pkg, 'resources'));
local_write(fullfile(pkg, 'bin', 'pseudoct'), {'#!/bin/sh'; 'exit 0'});
local_write(fullfile(pkg, 'manifest.json'), {'{"schema": "synthetic-installed-manifest"}'});
config = struct('mode', 'local', 'atlas_root', fullfile(pkg, 'resources'));
resources_dict = fullfile(pkg, 'resources', 'spm_dicom_dict.mat');

% Installed, dictionary missing: fail closed in setup for a validate purpose too.
setenv('PSEUDOCT_INSTALL_ROOT', pkg);
local_expect('pseudo_CT:SpmDicomDictMissing', ...
    @() setup_pseudo_CT_paths(pkg, config, 'validate', false, false));

% Installed, dictionary present: setup joins the resources folder, and the
% dictionary resolves by bare name inside the installed package.
dict = struct('values', 1); %#ok<NASGU>
save(resources_dict, 'dict', '-v6');
local_write_resources(fullfile(pkg, 'resources'));
% A required resource file missing: setup fails closed and names the file.
delete(fullfile(pkg, 'resources', 'ch2.nii'));
local_expect_message('pseudo_CT:MissingResource', 'ch2.nii', ...
    @() setup_pseudo_CT_paths(pkg, config, 'validate', false, false));
local_write(fullfile(pkg, 'resources', 'ch2.nii'), {'synthetic resource'});
setup_pseudo_CT_paths(pkg, config, 'validate', false, false);
assert(strcmp(which('spm_dicom_dict.mat'), resources_dict), ...
    'Installed setup must put the packaged dictionary first on the path.');

% Source mode: the check does not run, so a missing dictionary is not an error.
setenv('PSEUDOCT_INSTALL_ROOT', '');
source_config = struct('mode', 'local', 'atlas_root', fullfile(work, 'no-atlas'));
setup_pseudo_CT_paths(repo, source_config, 'validate', false, false);
fprintf('Installed setup dictionary checks passed.\n');
end

function local_expect_message(identifier, fragment, handle)
raised = '';
message = '';
try
    feval(handle);
catch ME
    raised = ME.identifier;
    message = ME.message;
end
assert(strcmp(raised, identifier), ...
    sprintf('Expected %s, got [%s].', identifier, raised));
assert(~isempty(strfind(message, fragment)), ...
    sprintf('The error must name %s: %s', fragment, message));
end

function local_write_resources(resources_dir)
%LOCAL_WRITE_RESOURCES Synthetic installed resource files (existence only).
names = {'ch2.nii'; 'new_segment_batch.mat'; ...
    'dartel_existing_template_batch.mat'; 'create_inverse_warped_batch.mat'; ...
    'Template_1.nii'; 'Template_2.nii'; 'Template_3.nii'; ...
    'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'; 'TPM.nii'; ...
    'Atlas_synthetic.nii'};
for ii = 1:length(names)
    local_write(fullfile(resources_dir, names{ii}), {'synthetic resource'});
end
end

function local_restore(old_path, old_install)
path(old_path);
setenv('PSEUDOCT_INSTALL_ROOT', old_install);
end

function local_expect(identifier, handle)
raised = false;
try
    feval(handle);
catch ME
    raised = true;
    if ~strcmp(ME.identifier, identifier)
        error('test_setup_spm_dictionary:Identifier', 'Expected %s, got %s: %s', ...
            identifier, ME.identifier, ME.message);
    end
end
if ~raised
    error('test_setup_spm_dictionary:NoError', ...
        'Expected %s but no error was raised.', identifier);
end
end

function local_write(path_text, lines)
fid = fopen(path_text, 'w');
if fid == -1
    error('test_setup_spm_dictionary:Write', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
for ii = 1:length(lines)
    fprintf(fid, '%s\n', lines{ii});
end
end
