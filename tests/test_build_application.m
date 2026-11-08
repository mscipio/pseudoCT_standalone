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
% The preflight requires SPM's DICOM dictionary; a synthetic one is enough here.
dict_synthetic = struct('values', 1); %#ok<NASGU>
save(fullfile(fake_spm, 'spm_dicom_dict.mat'), 'dict_synthetic', '-v6');
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

% MEX inputs whose folder is already on the search path report exist type 3.
local_mex_on_path_case(repo, work, sentinel);

% Synthetic package: inventory, manifest agreement, and tamper detection.
pkg = fullfile(work, 'pkg');
rels = {'standalone/pseudoct_standalone'; 'payload/pseudoct_worker'; ...
    'resources/Atlas_a.nii'; 'bin/pseudoct'};
bodies = {'standalone stub'; 'payload stub'; 'atlas bytes'; 'launcher'};
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

launcher_path = fullfile(pkg, 'bin', 'pseudoct');
delete(launcher_path);
local_expect('pseudo_CT:PackageTampered', @() verify_application_package(pkg));
local_write(launcher_path, bodies(4));

restored = verify_application_package(pkg);
assert(restored.passed, 'Restored synthetic package must verify.');
assert(exist(sentinel, 'file') ~= 2, 'mcc was reached during the tests.');

% Single mechanism: the SPM DICOM dictionary is an unchanged resources/ file copied
% from the SPM root, not a worker -a input; the atlas TPM.nii is a resource too.
plan_text = local_read_text(fullfile(repo, 'scripts', 'build_application.m'));
assert(isempty(strfind(plan_text, 'fullfile(spm, ''spm_dicom_dict.mat'')')), ...
    'The payload -a plan must no longer compile the SPM DICOM dictionary.');
assert(~isempty(strfind(plan_text, '{''spm_dicom_dict.mat''}')), ...
    'The resource list must include spm_dicom_dict.mat.');
assert(~isempty(strfind(plan_text, 'source_dir = opt.spmroot;')), ...
    'The dictionary must be copied from the selected SPM root.');
assert(~isempty(strfind(plan_text, '''TPM.nii''')), ...
    'The atlas resources must include TPM.nii.');

% The dictionary check (used by the worker before any SPM call): missing,
% unreadable and present cases, in a scratch folder.
addpath(fullfile(repo, 'src', 'science', 'current'), '-begin');
dict_cleanup = onCleanup(@() rmpath(fullfile(repo, 'src', 'science', 'current'))); %#ok<NASGU>
dict_dir = fullfile(work, 'dict');
mkdir(dict_dir);
local_expect('pseudo_CT:SpmDicomDictMissing', ...
    @() pseudo_CT_check_spm_dicom_dict(dict_dir));
local_write_bytes(fullfile(dict_dir, 'spm_dicom_dict.mat'), uint8([]));
local_expect('pseudo_CT:SpmDicomDictUnreadable', ...
    @() pseudo_CT_check_spm_dicom_dict(dict_dir));
local_write_bytes(fullfile(dict_dir, 'spm_dicom_dict.mat'), uint8('not a MAT file'));
local_expect('pseudo_CT:SpmDicomDictUnreadable', ...
    @() pseudo_CT_check_spm_dicom_dict(dict_dir));
dict = struct('values', 1); %#ok<NASGU>
save(fullfile(dict_dir, 'spm_dicom_dict.mat'), 'dict', '-v6');
found = pseudo_CT_check_spm_dicom_dict(dict_dir);
assert(strcmp(found, fullfile(dict_dir, 'spm_dicom_dict.mat')), ...
    'A present dictionary must return its absolute path.');
assert(strcmp(which('spm_dicom_dict.mat'), found), ...
    'The dictionary must resolve by its bare name once joined.');
rmpath(dict_dir);
end

function local_mex_on_path_case(repo, work, sentinel)
%LOCAL_MEX_ON_PATH_CASE Dry-run preflight accepts SPM MEX inputs on the path.
%   exist reports a MEX-file on the search path as type 3, not 2. The SPM root
%   is added to the path here, so the case does not depend on folders left by
%   earlier suites. The path is restored when this function returns.
old_path = path();
cleanup_path = onCleanup(@() path(old_path)); %#ok<NASGU>
spm_root = fullfile(repo, 'external', 'spm8-r6313');
addpath(spm_root, '-begin');
mex_file = fullfile(spm_root, 'spm_slice_vol.mexa64');
if exist(mex_file, 'file') ~= 3
    error('test_build_application:MexType', ...
        'Expected exist type 3 for a MEX file on the path, got %d.', exist(mex_file, 'file'));
end
out_root = fullfile(work, 'mex-on-path');
report = build_application('R2010b', 'OutputRoot', out_root);
if ~strcmp(report.mode, 'dry-run') || report.mcc_invoked
    error('test_build_application:MexDryRun', 'Dry run with a MEX on the path must not invoke mcc.');
end
if exist(fullfile(out_root, 'R2010b'), 'dir') == 7 || exist(sentinel, 'file') == 2
    error('test_build_application:MexDryRun', 'Dry run must not write a package or reach mcc.');
end
end

function local_write_bytes(path_text, bytes)
fid = fopen(path_text, 'w');
if fid == -1
    error('test_build_application:Write', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, bytes, 'uint8');
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

function text = local_read_text(path_text)
fid = fopen(path_text, 'r');
if fid == -1
    error('test_build_application:Read', 'Cannot read %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = fscanf(fid, '%c');
end

function hex = local_sha256(path_text)
[status, out] = system(sprintf('sha256sum "%s"', path_text));
if status ~= 0
    error('test_build_application:Hash', 'sha256sum failed for %s.', path_text);
end
hex = regexp(out, '^[0-9a-f]{64}', 'match', 'once');
end
