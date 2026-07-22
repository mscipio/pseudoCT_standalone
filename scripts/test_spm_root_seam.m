function test_spm_root_seam()
%TEST_SPM_ROOT_SEAM RED-first profile-owned SPM resolution checks.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'config'));
fake_root = tempname;
mkdir(fake_root);
mkdir(fullfile(fake_root, 'spm8-r6313'));
cleanup = onCleanup(@() rmdir(fake_root, 's')); %#ok<NASGU>

manifest = struct('name', 'local-current', ...
                  'spm_root', fullfile(fake_root, 'spm8-r6313'));
setenv('PSEUDOCT_SPM_ROOT', fullfile(fake_root, 'wrong-root'));
setenv('PSEUDOCT_SPM_VARIANT', 'wrong-variant');
env_cleanup = onCleanup(@() clear_spm_env()); %#ok<NASGU>

[resolved, label] = pseudo_CT_compute_spm_root(manifest, fake_root);
assert(strcmp(resolved, manifest.spm_root));
assert(~isempty(strfind(label, 'local-current')));
[resolved_again, ~] = pseudo_CT_resolve_spm_root(fake_root, manifest);
assert(strcmp(resolved_again, manifest.spm_root));

rmdir(manifest.spm_root, 's');
failed = false;
try
    pseudo_CT_compute_spm_root(manifest, fake_root);
catch ME
    failed = strcmp(ME.identifier, 'SPM_ROOT:NotFound');
end
assert(failed, 'Missing profile-owned SPM root must fail with SPM_ROOT:NotFound.');
fprintf('=== SPM root seam tests: 3/3 passed ===\n');
end

function clear_spm_env()
setenv('PSEUDOCT_SPM_ROOT', '');
setenv('PSEUDOCT_SPM_VARIANT', '');
end
