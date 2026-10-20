function test_mlsc_release_assembly()
%TEST_MLSC_RELEASE_ASSEMBLY Bounded assembly tests (synthetic, no mcc/science).
%   Offline only: synthetic staged packages under
%   scratch/release_gate/assembly_fixtures/ (ignored), read-only git
%   commit/tree/archive resolution against HEAD, disk reads of the pinned
%   MCR identity. The compiler is unreachable (only the assembly script,
%   the gate helper, and the publication validator run, all with fixture
%   manifests), no science, no SSH/Slurm, no publish/deploy, no tag, and
%   no worktree creation. Covers: valid fixtures assemble (archive under
%   scratch/ with a single versioned prefix, required members, hashes
%   recomputed from the actual archive bytes); each negative (missing
%   package, dist/ as source, wrong commit, tampered packaged file,
%   missing Gate-A record, source-version mismatch, slash tag refused as
%   a non-file-safe label) blocks with error id
%   pseudo_CT:MLSCReleaseGate and an explicit reason.
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
addpath(fullfile(root_dir, 'scripts'), '-begin');

gate_root = fullfile(root_dir, 'scratch', 'release_gate');
if exist(gate_root, 'dir') ~= 7
    [ok_gate, msg_gate] = mkdir(gate_root);
    assert(ok_gate, 'Cannot create gate staging dir: %s.', msg_gate);
end
run_root = fullfile(gate_root, 'assembly_fixtures');
if exist(run_root, 'dir') == 7
    rmdir(run_root, 's');
end
mkdir(run_root);
cleanup_root = onCleanup(@() local_cleanup(run_root)); %#ok<NASGU>

pinned = mlsc_current_validate('pinned_mcr_root');
assert(strcmp(pinned, '/usr/pubsw/common/matlab/26.1'), 'Pinned MCR_ROOT drifted.');
assert(exist(pinned, 'dir') == 7, 'Pinned MCR_ROOT unavailable for assembly fixtures.');

[s_head, o_head] = system(sprintf('git -C "%s" --no-pager rev-parse HEAD 2>&1', root_dir));
commit = lower(strtrim(o_head));
assert(s_head == 0 && length(commit) == 40, 'HEAD fixture unresolvable.');
tree = mlsc_release_gate('release_tree', root_dir, commit);
[s_cl, o_cl] = system(sprintf('git -C "%s" --no-pager show %s:CHANGELOG.md 2>&1', root_dir, commit));
assert(s_cl == 0, 'HEAD CHANGELOG fixture unreadable.');
head_version = strtrim(strtok(strtrim(o_cl), char(10)));
assert(~isempty(regexp(head_version, '^[0-9]+\.[0-9]+\.[0-9]+$', 'once')), 'HEAD version shape unexpected.');

% A0: valid fixtures assemble; archive contents verified from the bytes.
A = local_make_valid_package(run_root, 'case-pass', commit, tree, pinned);
out_here = fullfile(run_root, 'case-pass', 'assembly');
archive = assemble_mlsc_release('PackageDir', A.pkg, 'ReleaseCommit', commit, ...
    'SourceVersion', head_version, 'GateARecord', A.record, ...
    'OutputDir', out_here, 'RepoRoot', root_dir);
assert(ischar(archive) && exist(archive, 'file') == 2, 'Assembly archive missing.');
assert(~isempty(strfind(archive, [filesep 'scratch' filesep])), 'Archive is not under scratch/.');
assert(isempty(strfind(archive, [filesep 'dist' filesep])), 'Archive must never use dist/.');
info_arc = dir(archive);
assert(info_arc(1).bytes > 0, 'Assembly archive is empty.');
archive_sha = mlsc_release_gate('sha256_file', archive);
assert(mlsc_release_gate('is_valid_sha256', archive_sha), 'Archive SHA-256 unavailable.');
[s_members, o_members] = system(sprintf('tar -tzf ''%s'' 2>&1', archive));
assert(s_members == 0, 'Archive listing failed.');
members = local_lines(o_members);
prefixes = {};
for kk = 1:numel(members)
    tok = regexp(members{kk}, '^([^/]+)/', 'tokens', 'once');
    assert(~isempty(tok), 'Archive member escapes the versioned prefix.');
    prefixes{end + 1, 1} = tok{1}; %#ok<AGROW>
end
assert(isequal(unique(prefixes), {prefixes{1}}), 'Archive carries more than one top level.');
assert(~isempty(strfind(prefixes{1}, 'pseudoCT_mlsc-current-')), 'Archive prefix is not versioned.');
required = {'source/CHANGELOG.md'; 'compiled/payload_build/run_mlsc_current_payload.sh'; ...
    'compiled/mlsc_current_build.mat'; 'MCR_COMPAT.txt'; 'RELEASE_PROVENANCE.txt'};
for kk = 1:numel(required)
    assert(any(strcmp(members, [prefixes{1} '/' required{kk}])), ...
        'Archive is missing required member %s.', required{kk});
end
fprintf('ASSEMBLY-A0 PASS: valid fixtures assemble with verified archive contents.\n');

% N1: missing staged package blocks.
local_expect_block(@() assemble_mlsc_release('PackageDir', ...
    fullfile(run_root, 'case-n1', 'absent-package'), 'ReleaseCommit', commit, ...
    'SourceVersion', head_version, ...
    'GateARecord', fullfile(run_root, 'absent_gate_a.mat'), ...
    'OutputDir', fullfile(run_root, 'case-n1', 'assembly'), 'RepoRoot', root_dir), 'missing');
fprintf('ASSEMBLY-N1 PASS: missing package blocks.\n');

% N2: dist/ is never an assembly source (even though the directory exists).
Q = local_make_valid_package(run_root, 'case-n2', commit, tree, pinned);
local_expect_block(@() assemble_mlsc_release('PackageDir', ...
    fullfile(root_dir, 'dist', 'mlsc_current_build'), 'ReleaseCommit', commit, ...
    'SourceVersion', head_version, 'GateARecord', Q.record, ...
    'OutputDir', fullfile(run_root, 'case-n2', 'assembly'), 'RepoRoot', root_dir), 'dist/');
fprintf('ASSEMBLY-N2 PASS: dist/ as source rejected.\n');

% N3: wrong commit blocks (validator propagates, no weakening).
Q = local_make_valid_package(run_root, 'case-n3', commit, tree, pinned);
loaded = load(Q.buildmat);
build = loaded.build;
build.source_commit = repmat('b', 1, 40);
save(Q.buildmat, 'build');
local_expect_block(@() assemble_mlsc_release('PackageDir', Q.pkg, ...
    'ReleaseCommit', commit, 'SourceVersion', head_version, 'GateARecord', Q.record, ...
    'OutputDir', fullfile(run_root, 'case-n3', 'assembly'), 'RepoRoot', root_dir), 'source_commit');
fprintf('ASSEMBLY-N3 PASS: wrong commit blocks.\n');

% N4: tampered packaged file blocks (package-vs-build diff propagates).
Q = local_make_valid_package(run_root, 'case-n4', commit, tree, pinned);
fid = fopen(fullfile(Q.pkg, 'payload_build', 'readme.txt'), 'a');
assert(fid ~= -1, 'Tamper fixture failed.');
fwrite(fid, 'tampered');
fclose(fid);
local_expect_block(@() assemble_mlsc_release('PackageDir', Q.pkg, ...
    'ReleaseCommit', commit, 'SourceVersion', head_version, 'GateARecord', Q.record, ...
    'OutputDir', fullfile(run_root, 'case-n4', 'assembly'), 'RepoRoot', root_dir), 'readme.txt');
fprintf('ASSEMBLY-N4 PASS: tampered packaged file blocks.\n');

% N5: missing Gate-A record blocks.
Q = local_make_valid_package(run_root, 'case-n5', commit, tree, pinned);
local_expect_block(@() assemble_mlsc_release('PackageDir', Q.pkg, ...
    'ReleaseCommit', commit, 'SourceVersion', head_version, ...
    'GateARecord', fullfile(run_root, 'case-n5', 'absent_gate_a.mat'), ...
    'OutputDir', fullfile(run_root, 'case-n5', 'assembly'), 'RepoRoot', root_dir), 'Gate-A');
fprintf('ASSEMBLY-N5 PASS: missing Gate-A binding blocks.\n');

% N6: source-version mismatch blocks (staged CHANGELOG vs expectation).
Q = local_make_valid_package(run_root, 'case-n6', commit, tree, pinned);
local_expect_block(@() assemble_mlsc_release('PackageDir', Q.pkg, ...
    'ReleaseCommit', commit, 'SourceVersion', '9.9.9', 'GateARecord', Q.record, ...
    'OutputDir', fullfile(run_root, 'case-n6', 'assembly'), 'RepoRoot', root_dir), 'SourceVersion');
fprintf('ASSEMBLY-N6 PASS: source-version mismatch blocks.\n');

% N7: slash tag refused as a non-file-safe archive label (the gate tag
%   charset admits '/', the archive label charset does not).
Q = local_make_valid_package(run_root, 'case-n7', commit, tree, pinned);
local_expect_block(@() assemble_mlsc_release('PackageDir', Q.pkg, ...
    'ReleaseTag', 'v2.8.4/x', 'GateARecord', Q.record, ...
    'OutputDir', fullfile(run_root, 'case-n7', 'assembly'), 'RepoRoot', root_dir), 'file-safe');
fprintf('ASSEMBLY-N7 PASS: slash tag refused as archive label.\n');

fprintf('=== MLSC release-assembly tests passed: 1 positive + 7 negative ===\n');
end

function P = local_make_valid_package(root_dir, case_name, commit, tree, pinned)
case_root = fullfile(root_dir, case_name);
mkdir(case_root);
pkg = fullfile(case_root, 'package');
mkdir(pkg);
bd = fullfile(pkg, 'payload_build');
mkdir(bd);
runner = fullfile(bd, 'run_mlsc_current_payload.sh');
exe = fullfile(bd, 'mlsc_current_payload');
readme = fullfile(bd, 'readme.txt');
local_write(runner, ['#!/bin/sh' char(10) '# assembly fixture runner ' case_name char(10)]);
local_write(exe, ['assembly-fixture-executable-bytes-' case_name]);
local_write(readme, ['assembly fixture readme ' case_name]);
runner_sha = local_sha_hex(runner);
exe_sha = local_sha_hex(exe);
resources = struct();
resources.schema = 'pseudo-CT.mlsc-current-resources/v1';
resources.manifest_version = 1;
resources.atlas_dir = fullfile(case_root, 'Batch_atlas');
resources.native_platform = 'glnxa64';
resources.native_arch = 'glnxa64';
resources.native_validation = 't007-gate-a-pending: existence-only; production loadability evidence comes later';
resmat = fullfile(pkg, 'mlsc_current_resources.mat');
save(resmat, 'resources');
res_sha = local_sha_hex(resmat);
[pfiles, psums, pfp] = mlsc_release_gate('inventory_dir', pkg, ...
    {'mlsc_current_build.mat', 'mlsc_current_build.txt'});
src_fp = local_sha_hex(readme);
build = struct();
build.schema = 'pseudo-CT.mlsc-current-build/v1';
build.manifest_version = 1;
build.runner = runner;
build.mcr_root = pinned;
build.release = 'R2026a';
build.update_minimum = 2;
build.mcr_version = [26 1];
build.arch = 'glnxa64';
build.generation = '26.1';
build.runner_checksum = runner_sha;
build.source_commit = commit;
build.source_provenance_fingerprint = src_fp;
build.required_outputs = {'att_map.nii'; 'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
build.build_mode = 'release-candidate';
build.release_tag = '';
build.release_commit = commit;
build.release_tree = tree;
build.packaged_files = pfiles;
build.packaged_checksums = psums;
build.packaged_files_fingerprint = pfp;
build.resource_fingerprint = res_sha;
build.executable_fingerprint = exe_sha;
build.compiler_identity = 'MATLAB Compiler 26.1 (R2026a)';
build.required_toolboxes = {'Image_Toolbox'; 'Statistics_Toolbox'; 'Compiler'};
build.runner_contract = 'run_mlsc_current_payload.sh <MCR_ROOT> <phase> <job_manifest> <resource_manifest>';
build.gate_a_status = 'pending: fixture only';
buildmat = fullfile(pkg, 'mlsc_current_build.mat');
save(buildmat, 'build');
build_sha = local_sha_hex(buildmat);
native = fullfile(case_root, 'spm_sample_vol.mexa64');
local_write(native, ['assembly-fixture-native-' case_name]);
nat_sha = local_sha_hex(native);
actual_rt = mlsc_current_validate('actual_identity', pinned);
gate_a = struct();
gate_a.schema = 'pseudo-CT.mlsc-current-gate-a/v1';
gate_a.manifest_version = 1;
gate_a.source_commit = commit;
gate_a.source_provenance_fingerprint = src_fp;
gate_a.mcr_root = pinned;
gate_a.release = actual_rt.release;
gate_a.version = actual_rt.version;
gate_a.update_minimum = build.update_minimum;
gate_a.update_actual = actual_rt.update;
gate_a.mcr_version = actual_rt.mcr_version;
gate_a.arch = actual_rt.arch;
gate_a.generation = actual_rt.generation;
gate_a.runner = runner;
gate_a.runner_checksum = runner_sha;
gate_a.build_exe = exe;
gate_a.build_exe_checksum = exe_sha;
gate_a.build_manifest = buildmat;
gate_a.build_manifest_checksum = build_sha;
gate_a.resource_manifest = resmat;
gate_a.resource_manifest_checksum = res_sha;
gate_a.native_names = {'spm_sample_vol.mexa64'};
gate_a.native_paths = {native};
gate_a.native_checksums = {nat_sha};
gate_a.native_results = {'pass'};
gate_a.launcher_result = 'pass';
gate_a.runtime_lib_result = 'pass';
gate_a.prepare_result = 'pass';
gate_a.compute_result = 'pass';
gate_a.overall_result = 'pass';
record = fullfile(case_root, 'mlsc_current_gate_a.mat');
save(record, 'gate_a');
P = struct('pkg', pkg, 'buildmat', buildmat, 'resmat', resmat, 'record', record);
end

function local_expect_block(thunk, reason_substr)
failed = false;
actual_id = '';
actual_msg = '';
try
    thunk();
catch ME
    failed = true;
    actual_id = ME.identifier;
    actual_msg = ME.message;
end
assert(failed, 'Fail-closed assembly did not reject.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCReleaseGate'), 'Unexpected failure identifier: %s.', actual_id);
assert(~isempty(strfind(actual_msg, reason_substr)), 'Assembly reason missing "%s": %s.', reason_substr, actual_msg);
end

function lines = local_lines(txt)
lines = {};
if isempty(txt)
    return;
end
parts = strsplit(strtrim(txt), char(10));
for kk = 1:numel(parts)
    t = strtrim(parts{kk});
    if ~isempty(t)
        lines{end + 1, 1} = t; %#ok<AGROW>
    end
end
end

function hex = local_sha_hex(path_name)
fid = fopen(path_name, 'r');
assert(fid ~= -1, 'Hash fixture could not be read.');
raw = fread(fid, inf, '*uint8')';
fclose(fid);
try
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(raw);
    bytes = typecast(digest.digest(), 'uint8');
    hex = lower(reshape(dec2hex(bytes, 2)', 1, []));
    assert(length(hex) == 64, 'SHA fixture failed.');
    return;
catch %#ok<CTCH>
end
single_quote = char(39);
q = [single_quote strrep(path_name, single_quote, [single_quote '"' single_quote '"' single_quote]) single_quote];
[status, out] = system(['sha256sum ' q ' 2>/dev/null']);
assert(status == 0, 'SHA fixture unavailable.');
tok = regexp(strtrim(out), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', 'tokens', 'once');
assert(~isempty(tok), 'SHA fixture parse failed.');
hex = lower(strtrim(tok{1}));
end

function local_write(path_name, text)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Fixture could not be created.');
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
