function test_build_application()
%TEST_BUILD_APPLICATION Offline build preflight and package integrity checks.
%   Never calls mcc: a sentinel mcc is placed first on the path and must not
%   run. Uses only dry-run mode; no test passes 'Mode', 'build'. Synthetic
%   package files only.

repo = fileparts(fileparts(mfilename('fullpath')));
scratch_root = getenv('PSEUDOCT_TEST_SCRATCH');
if isempty(scratch_root)
    scratch_root = tempdir;
end
work = tempname(scratch_root);
mkdir(work);

old_path = path();
cleanup_path = onCleanup(@() path(old_path));
addpath(fullfile(repo, 'scripts'), '-begin');
shadow = fullfile(work, 'shadow');
mkdir(shadow);
sentinel = fullfile(work, 'mcc_reached.txt');
local_write(fullfile(shadow, 'mcc.m'), { ...
    'function mcc(varargin)'; ...
    ['fid = fopen(''' sentinel ''', ''a''); fprintf(fid, ''reached''); fclose(fid);']; ...
    'error(''pseudo_CT:TestMccReached'', ''mcc reached from a dry run.'');'; 'end'});
addpath(shadow, '-begin');
assert(strcmp(which('mcc'), fullfile(shadow, 'mcc.m')), 'Sentinel mcc is not first on the path.');

% Explicit release is mandatory and must be well formed.
local_expect('pseudo_CT:BuildUsage', @() build_application());
local_expect('pseudo_CT:BuildUsage', @() build_application('2010b'));
local_expect('pseudo_CT:BuildUsage', @() build_application('R2010b', 'Mode'));

% Release mismatch and missing dependencies fail in preflight.
local_expect('pseudo_CT:BuildReleaseMismatch', @() build_application('R2026a'));
local_expect('pseudo_CT:BuildDependency', ...
    @() build_application('R2010b', 'SpmRoot', fullfile(work, 'no-spm')));
local_expect('pseudo_CT:BuildDependency', ...
    @() build_application('R2010b', 'LockSha256', repmat('0', 1, 64)));

% SPM root with Contents.m but no matlabbatch/ or mex inputs: every mcc
% input is checked in preflight, before any compiler call.
fake_spm = fullfile(work, 'fake-spm');
mkdir(fake_spm);
local_write(fullfile(fake_spm, 'Contents.m'), {'% synthetic SPM root for preflight tests'});
local_expect('pseudo_CT:BuildCompileInputMissing', ...
    @() build_application('R2010b', 'SpmRoot', fake_spm));

% Output rules: no overwrite, no source or dependency locations.
existing_out = fullfile(work, 'existing');
mkdir(fullfile(existing_out, 'R2010b'));
local_expect('pseudo_CT:BuildOutputExists', ...
    @() build_application('R2010b', 'OutputRoot', existing_out));
local_expect('pseudo_CT:BuildOutputRejected', ...
    @() build_application('R2010b', 'OutputRoot', fullfile(repo, 'src', 'out')));

% Successful dry run: reports identities, writes nothing, never reaches mcc.
fresh_out = fullfile(work, 'fresh');
report = build_application('R2010b', 'OutputRoot', fresh_out);
assert(strcmp(report.mode, 'dry-run') && ~report.mcc_invoked, 'Dry run must not invoke mcc.');
assert(exist(fullfile(fresh_out, 'R2010b'), 'dir') ~= 7, 'Dry run must not create a package.');
assert(exist(sentinel, 'file') ~= 2, 'mcc was reached during the dry run.');

% Synthetic package: inventory, manifest agreement, and tamper detection.
pkg = fullfile(work, 'pkg');
rels = {'app/run_pseudo_CT'; 'payload/mlsc_current_payload'; ...
    'resources/Atlas_a.nii'; 'launchers/pseudoct'};
bodies = {'app stub'; 'payload stub'; 'atlas bytes'; 'launcher'};
for kk = 1:numel(rels)
    mkdir(fileparts(fullfile(pkg, rels{kk})));
    local_write(fullfile(pkg, rels{kk}), bodies(kk));
end
manifest_path = fullfile(pkg, 'application_manifest.txt');
manifest_lines = {'schema pseudo-CT.application-package/v1'; 'release R2010b'; ...
    'file_count 5'; 'inventory_file SHA256SUMS'};
local_write(manifest_path, manifest_lines);
all_rels = [rels; {'application_manifest.txt'}];
sums = cell(numel(all_rels), 1);
for kk = 1:numel(all_rels)
    sums{kk} = sprintf('%s  %s', local_sha256(fullfile(pkg, all_rels{kk})), all_rels{kk});
end
local_write(fullfile(pkg, 'SHA256SUMS'), sums);
verified = verify_application_package(pkg);
assert(verified.passed && verified.file_count == 5, 'Clean synthetic package must verify.');

atlas_path = fullfile(pkg, 'resources', 'Atlas_a.nii');
local_write(atlas_path, {'tampered'});
local_expect('pseudo_CT:PackageTampered', @() verify_application_package(pkg));
local_write(atlas_path, bodies(3));

local_write(manifest_path, [manifest_lines(1:2); {'file_count 4'}; manifest_lines(4)]);
local_expect('pseudo_CT:PackageTampered', @() verify_application_package(pkg));
local_write(manifest_path, manifest_lines);

extra_path = fullfile(pkg, 'extra.txt');
local_write(extra_path, {'unexpected'});
local_expect('pseudo_CT:PackageTampered', @() verify_application_package(pkg));
delete(extra_path);

% Dot-prefixed entries are not exempt from the unexpected-file check.
dot_path = fullfile(pkg, '.extra');
local_write(dot_path, {'unexpected hidden file'});
local_expect('pseudo_CT:PackageTampered', @() verify_application_package(pkg));
delete(dot_path);
mkdir(fullfile(pkg, '.hidden'));
hidden_path = fullfile(pkg, '.hidden', 'extra');
local_write(hidden_path, {'unexpected hidden folder file'});
local_expect('pseudo_CT:PackageTampered', @() verify_application_package(pkg));
delete(hidden_path);
rmdir(fullfile(pkg, '.hidden'));

launcher_path = fullfile(pkg, 'launchers', 'pseudoct');
delete(launcher_path);
local_expect('pseudo_CT:PackageTampered', @() verify_application_package(pkg));
local_write(launcher_path, bodies(4));

restored = verify_application_package(pkg);
assert(restored.passed, 'Restored synthetic package must verify.');
assert(exist(sentinel, 'file') ~= 2, 'mcc was reached during the tests.');
end

function local_expect(identifier, handle)
raised = false;
try
    feval(handle);
catch ME
    raised = true;
    if ~strcmp(ME.identifier, identifier)
        error('test_build_application:Identifier', 'Expected %s, got %s: %s', ...
            identifier, ME.identifier, ME.message);
    end
end
if ~raised
    error('test_build_application:NoError', 'Expected %s but no error was raised.', identifier);
end
end

function local_write(path_text, lines)
fid = fopen(path_text, 'w');
if fid == -1
    error('test_build_application:Write', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid));
for kk = 1:numel(lines)
    fprintf(fid, '%s\n', lines{kk});
end
end

function hex = local_sha256(path_text)
[status, out] = system(sprintf('sha256sum "%s"', path_text));
if status ~= 0
    error('test_build_application:Hash', 'sha256sum failed for %s.', path_text);
end
hex = regexp(out, '^[0-9a-f]{64}', 'match', 'once');
end
