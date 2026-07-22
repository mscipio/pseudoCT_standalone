function test_atlas_seam()
%TEST_ATLAS_SEAM RED-first manifest-owned atlas checks.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'config'));
fake_root = tempname;
mkdir(fake_root);
mkdir(fullfile(fake_root, 'spm8-r6313'));
make_atlas(fake_root);
cleanup = onCleanup(@() rmdir(fake_root, 's')); %#ok<NASGU>

manifest = pseudo_CT_profile_registry('local-current', fake_root);
other_atlas = fullfile(fake_root, 'other-atlas');
mkdir(other_atlas);
setenv('PSEUDOCT_BATCH_ATLAS', other_atlas);
env_cleanup = onCleanup(@() setenv('PSEUDOCT_BATCH_ATLAS', '')); %#ok<NASGU>
resolved = pseudo_CT_resolve_batch_atlas_path(fake_root, manifest);
assert(strcmp(resolved, manifest.atlas_assets.batch_atlas_path));

delete(fullfile(resolved, 'TPM.nii'));
failed = false;
try
    pseudo_CT_resolve_batch_atlas_path(fake_root, manifest);
catch ME
    failed = strcmp(ME.identifier, 'ATLAS:AssetMissing');
end
assert(failed, 'Missing manifest atlas assets must fail as ATLAS:AssetMissing.');
fprintf('=== Atlas seam tests: 2/2 passed ===\n');
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
