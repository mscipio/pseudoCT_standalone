function test_zero_background_seam()
%TEST_ZERO_BACKGROUND_SEAM RED-first profile-owned background checks.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'config'));
fake_root = tempname;
mkdir(fake_root);
mkdir(fullfile(fake_root, 'src'));
mkdir(fullfile(fake_root, 'src', 'config'));
mkdir(fullfile(fake_root, 'src', 'config', 'spm_profiles'));
write_profile_config(fullfile(fake_root, 'src', 'config', 'spm_profiles'), ...
    'local_current', '', 'r6313');
write_profile_config(fullfile(fake_root, 'src', 'config', 'spm_profiles'), ...
    'launchpad', '', 'r6313');
cleanup = onCleanup(@() rmdir(fake_root, 's')); %#ok<NASGU>

local_manifest = pseudo_CT_profile_registry('local-current', fake_root);
launchpad_manifest = pseudo_CT_profile_registry('launchpad', fake_root);
setenv('PSEUDOCT_ZERO_BACKGROUND', '1');
env_cleanup = onCleanup(@() setenv('PSEUDOCT_ZERO_BACKGROUND', '')); %#ok<NASGU>
assert(strcmp(pseudo_CT_zero_background_enabled(local_manifest), 'Yes'));
assert(strcmp(pseudo_CT_zero_background_enabled(launchpad_manifest), 'No'));
fprintf('=== Zero-background seam tests: 2/2 passed ===\n');
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
