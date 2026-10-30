function test_dependency_paths()
%TEST_DEPENDENCY_PATHS Verify installation-root dependency resolution.
%   This focused check is offline and does not run image processing.

root_dir = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
old_pwd = pwd();
addpath(fullfile(root_dir, 'src', 'config'), '-begin');
cleanup = onCleanup(@() local_restore(old_path, old_pwd)); %#ok<NASGU>

% Resolve from an unrelated working directory to prove mfilename, not pwd,
% anchors the versioned dependency layout.
cd(tempdir);
paths = pseudo_CT_dependency_paths();
assert(strcmp(paths.install_root, root_dir));
assert(strcmp(paths.spm_root, fullfile(root_dir, 'external', 'spm8-r6313')));
assert(strcmp(paths.spm8_dan_root, fullfile(root_dir, 'external', 'spm8-dan')));
assert(strcmp(paths.atlas_root, fullfile(root_dir, 'external', 'Batch_atlas')));
assert(strcmp(paths.legacy_root, ...
    fullfile(root_dir, 'compiled', 'legacy-v2.0.0')));
assert(strcmp(paths.legacy_runner, fullfile(paths.legacy_root, ...
    'run_Pseudo_CT_launchpad.sh')));
assert(strcmp(paths.legacy_defaults, fullfile(paths.legacy_root, ...
    'default_pseudo_CT_package_deployed.mat')));
assert(strcmp(paths.legacy_batch_templates, ...
    fullfile(paths.legacy_root, 'Batch_atlas')));
assert(strcmp(paths.current_root, fullfile(root_dir, 'compiled', 'current')));

% Profiles use the same pinned local roots, including the older SPM8 build
% selected only by the deprecated near-parity profile.
profile_dir = fullfile(root_dir, 'src', 'config', 'profiles');
addpath(profile_dir, '-begin');
for fn = {'local_current', 'mlsc_current', 'local_legacy', ...
        'mlsc_legacy', 'launchpad_legacy', 'local_mprage_only', 'devel'}
    clear(fn{1});
    config = feval(fn{1});
    assert(strcmp(config.spm_root, paths.spm_root));
    assert(strcmp(config.atlas_root, paths.atlas_root));
    if strcmp(fn{1}, 'mlsc_current')
        assert(strcmp(config.current.build_manifest, ...
            fullfile(paths.current_root, 'mlsc_current_build.mat')));
        assert(strcmp(config.current.resource_manifest, ...
            fullfile(paths.current_root, 'mlsc_current_resources.mat')));
    end
end

deprecated_dir = fullfile(profile_dir, 'deprecated');
addpath(deprecated_dir, '-begin');
for fn = {'launchpad', 'launchpad_mprage_only'}
    clear(fn{1});
    config = feval(fn{1});
    assert(strcmp(config.spm_root, paths.spm_root));
    assert(strcmp(config.atlas_root, paths.atlas_root));
end
clear local_near_parity_r2010b;
config = local_near_parity_r2010b();
assert(strcmp(config.spm_root, paths.spm8_dan_root));
assert(strcmp(config.atlas_root, paths.atlas_root));

% Setup already owns the fail-closed root checks; exercise each missing-root
% path before any path additions or workflow dependencies are touched.
missing_spm = struct('spm_root', fullfile(root_dir, 'external', ...
    'absent-spm'), 'atlas_root', paths.atlas_root);
local_assert_setup_error(root_dir, missing_spm, 'pseudo_CT:SPMRootMissing');
missing_atlas = struct('spm_root', paths.spm_root, 'atlas_root', ...
    fullfile(root_dir, 'external', 'absent-atlas'));
local_assert_setup_error(root_dir, missing_atlas, ...
    'pseudo_CT:AtlasRootMissing');

fprintf('Dependency root resolution and missing-root checks passed.\n');
end

function local_assert_setup_error(root_dir, config, expected_id)
failed = false;
try
    setup_pseudo_CT_paths(root_dir, config);
catch ME
    failed = strcmp(ME.identifier, expected_id);
end
assert(failed, 'Missing packaged dependency did not fail closed: %s.', ...
    expected_id);
end

function local_restore(old_path, old_pwd)
path(old_path);
cd(old_pwd);
end
