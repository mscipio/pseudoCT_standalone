function test_vers_overrides_complete()
%TEST_VERS_OVERRIDES_COMPLETE RED-first completeness check for vers/.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'config'));
fake_root = tempname;
mkdir(fake_root);
mkdir(fullfile(fake_root, 'spm8-r6313'));
copyfile(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'spm8-r6313', 'Contents.m'), fullfile(fake_root, 'spm8-r6313'));
mkdir(fullfile(fake_root, 'vers'));
touch(fullfile(fake_root, 'vers', 'spm_vol_nifti.m'));
touch(fullfile(fake_root, 'vers', 'spm_preproc_write8.m'));
make_atlas(fake_root);
mkdir(fullfile(fake_root, 'src'));
mkdir(fullfile(fake_root, 'src', 'config'));
mkdir(fullfile(fake_root, 'src', 'config', 'spm_profiles'));
write_profile_config(fullfile(fake_root, 'src', 'config', 'spm_profiles'), ...
    'local_current', '../../../spm8-r6313', 'r6313');
touch(fullfile(fake_root, 'src', 'config', 'fs_setenv_530_from_launchpad.sh'));
manifest = pseudo_CT_profile_registry('local-current', fake_root);
cleanup = onCleanup(@() rmdir(fake_root, 's')); %#ok<NASGU>

failed = false;
try
    setup_pseudo_CT_paths(fake_root, manifest);
catch ME
    failed = strcmp(ME.identifier, 'VERS:Incomplete');
end

function write_profile_config(config_dir, function_name, root_name, revision)
fid = fopen(fullfile(config_dir, [function_name '.m']), 'w');
fprintf(fid, 'function c = %s()\n', function_name);
fprintf(fid, 'c.spm_root = ''%s'';\n', root_name);
fprintf(fid, 'c.expected_revision = ''%s'';\n', revision);
fprintf(fid, 'end\n');
fclose(fid);
rehash;
end
assert(failed, 'A missing override must fail as VERS:Incomplete.');
fprintf('=== Vers completeness tests: 1/1 passed ===\n');
end

function make_atlas(fake_root)
atlas = fullfile(fake_root, 'Batch_atlas');
mkdir(atlas);
required = {'TPM.nii'; 'ch2.nii'; 'Template_0.nii'; 'Template_1.nii'; ...
    'Template_2.nii'; 'Template_3.nii'; 'Template_4.nii'; 'Template_5.nii'; ...
    'Template_6.nii'};
for ii = 1:length(required), touch(fullfile(atlas, required{ii})); end
mkdir(fullfile(atlas, 'ganymed-ssh2-build250'));
touch(fullfile(atlas, 'ganymed-ssh2-build250', 'ganymed-ssh2-build250.jar'));
end

function touch(path)
fid = fopen(path, 'w');
if fid ~= -1, fclose(fid); end
end
