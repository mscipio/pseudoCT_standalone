function test_mlsc_release_gate(mode, fixture_root)
%TEST_MLSC_RELEASE_GATE Bounded release-gate tests (T001 seam + T002 validator).
%   Offline only: synthetic manifests/packages under
%   scratch/release_gate/validator_fixtures/ (ignored), read-only git
%   tag/tree resolution against the existing v2.8.4 tag, disk reads of
%   the pinned MCR identity. No compiler invocation (mcc is unreachable:
%   only the gate helper and the validator run, both with fixture
%   manifests), no science, no SSH/Slurm, no publish/deploy, no tag, and
%   no worktree creation in the real tree (N13 uses a synthetic
%   throwaway repo only). Covers: valid candidate passes prepublication
%   and postinstall; each negative (missing dist/CTF/resources, wrong
%   commit, wrong tag, wrong hash, stale dist, local/stale manifest,
%   tampered package file, tampered deploy copy, missing Gate-A record,
%   missing release identity, wrong expected fingerprint, dirty-worktree
%   reuse, bogus-anchor bypass under env overrides despite a clean
%   parent (plus pristine worktree/standalone accept and
%   subdir/invalid-metadata/wrong-commit refuse), unavailable release tree, incomplete
%   Gate-A, absent native evidence, deployment-path mismatch, foreign
%   manifest paths) blocks with error id pseudo_CT:MLSCReleaseGate and
%   an explicit reason.
%   Focused mode accepts an optional FixtureRoot so task-local outputs can
%   stay under the caller's allocated scratch directory.
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
addpath(fullfile(root_dir, 'scripts'), '-begin');
if nargin > 0
    if ~ischar(mode) || size(mode, 1) ~= 1 || ...
            ~(strcmp(mode, 'r2010b_artifact') || strcmp(mode, 'v310_exception'))
        error('pseudo_CT:MLSCReleaseGate', 'Unknown focused release-gate test mode.');
    end
    if nargin < 2
        fixture_root = '';
    end
    local_test_r2010b_exception(root_dir, fixture_root);
    return;
end

gate_root = fullfile(root_dir, 'scratch', 'release_gate');
if exist(gate_root, 'dir') ~= 7
    [ok_gate, msg_gate] = mkdir(gate_root);
    assert(ok_gate, 'Cannot create gate staging dir: %s.', msg_gate);
end
run_root = fullfile(gate_root, 'validator_fixtures');
if exist(run_root, 'dir') == 7
    rmdir(run_root, 's');
end
mkdir(run_root);
cleanup_root = onCleanup(@() local_cleanup(run_root)); %#ok<NASGU>

pinned = mlsc_current_validate('pinned_mcr_root');
assert(strcmp(pinned, '/usr/pubsw/common/matlab/26.1'), 'Pinned MCR_ROOT drifted.');
assert(exist(pinned, 'dir') == 7, 'Pinned MCR_ROOT unavailable for gate fixtures.');

tag = 'v2.8.4';
[s_tag, o_tag] = system(sprintf('git -C "%s" --no-pager rev-parse --verify "%s^{commit}" 2>&1', root_dir, tag));
commit = lower(strtrim(o_tag));
assert(s_tag == 0 && length(commit) == 40, 'Release tag fixture unresolvable.');
[s_tree, o_tree] = system(sprintf('git -C "%s" --no-pager rev-parse "%s^{tree}" 2>&1', root_dir, commit));
tree = lower(strtrim(o_tree));
assert(s_tree == 0 && length(tree) == 40, 'Release tree fixture unresolvable.');

% Pure seam sanity: strict SHA shape + deterministic inventory.
probe = fullfile(run_root, 'probe.txt');
local_write(probe, 'probe-bytes');
probe_sha = local_sha_hex(probe);
assert(mlsc_release_gate('is_valid_sha256', probe_sha), 'SHA seam failed.');
assert(~mlsc_release_gate('is_valid_sha256', 'not-a-hash'), 'SHA seam accepted garbage.');
fprintf('GATE-SEAM PASS: strict SHA-256 shape enforced.\n');

% P0: valid candidate passes both modes.
P = local_make_valid_package(run_root, 'case-pass', commit, tag, tree, pinned);
assert(validate_mlsc_release('prepublication', ...
    'PackageDir', P.pkg, ...
    'ReleaseTag', tag, 'ReleaseCommit', commit, ...
    'ExpectedFingerprint', P.src_fp, ...
    'GateARecord', P.record));
fprintf('GATE-P0-PREPUB PASS: valid candidate passes prepublication.\n');
assert(validate_mlsc_release('postinstall', ...
    'BuildManifest', P.deploy_buildmat, 'ResourceManifest', P.deploy_resmat, ...
    'ReleaseTag', tag, 'ReleaseCommit', commit, ...
    'ExpectedFingerprint', P.src_fp, ...
    'GateARecord', P.record, 'DeployRoot', P.deploy));
fprintf('GATE-P0-POSTINSTALL PASS: valid deployment copy passes postinstall.\n');

% N1: missing dist (no payload_build).
Q = local_make_valid_package(run_root, 'case-n1', commit, tag, tree, pinned);
rmdir(fullfile(Q.pkg, 'payload_build'), 's');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'payload_build');
fprintf('GATE-N1 PASS: missing dist blocks.\n');

% N2: missing CTF/executable.
Q = local_make_valid_package(run_root, 'case-n2', commit, tag, tree, pinned);
delete(fullfile(Q.pkg, 'payload_build', 'mlsc_current_payload'));
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'mlsc_current_payload');
fprintf('GATE-N2 PASS: missing CTF/executable blocks.\n');

% N3: missing resources.
Q = local_make_valid_package(run_root, 'case-n3', commit, tag, tree, pinned);
delete(fullfile(Q.pkg, 'mlsc_current_resources.mat'));
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'resource');
fprintf('GATE-N3 PASS: missing resources block.\n');

% N4: wrong commit.
Q = local_make_valid_package(run_root, 'case-n4', commit, tag, tree, pinned);
loaded = load(Q.buildmat);
build = loaded.build;
build.source_commit = repmat('b', 1, 40);
save(Q.buildmat, 'build');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'source_commit');
fprintf('GATE-N4 PASS: wrong commit blocks.\n');

% N4b: manifest built for another tag.
Q = local_make_valid_package(run_root, 'case-n4b', commit, 'v2.8.4-other', tree, pinned);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'ReleaseCommit', commit, 'GateARecord', Q.record), 'release tag');
fprintf('GATE-N4B PASS: tag-built-for mismatch blocks.\n');

% N5: wrong hash (tampered runner).
Q = local_make_valid_package(run_root, 'case-n5', commit, tag, tree, pinned);
fid = fopen(fullfile(Q.pkg, 'payload_build', 'run_mlsc_current_payload.sh'), 'a');
assert(fid ~= -1, 'Tamper fixture failed.');
fwrite(fid, '# tampered');
fclose(fid);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'runner');
fprintf('GATE-N5 PASS: wrong runner hash blocks.\n');

% N6: stale dist (extra file beyond inventory).
Q = local_make_valid_package(run_root, 'case-n6', commit, tag, tree, pinned);
local_write(fullfile(Q.pkg, 'payload_build', 'stale_leftover.txt'), 'stale');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'Stale extra');
fprintf('GATE-N6 PASS: stale dist blocks.\n');

% N7: local/stale manifest (not a release-candidate build).
Q = local_make_valid_package(run_root, 'case-n7', commit, tag, tree, pinned);
loaded = load(Q.buildmat);
build = loaded.build;
build.build_mode = 'local';
save(Q.buildmat, 'build');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'release-candidate');
fprintf('GATE-N7 PASS: non-release manifest blocks.\n');

% N8: package-vs-build diff (tampered non-runner packaged file).
Q = local_make_valid_package(run_root, 'case-n8', commit, tag, tree, pinned);
fid = fopen(fullfile(Q.pkg, 'payload_build', 'readme.txt'), 'a');
assert(fid ~= -1, 'Tamper fixture failed.');
fwrite(fid, 'tampered');
fclose(fid);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'readme.txt');
fprintf('GATE-N8 PASS: package-vs-build diff blocks.\n');

% N9: deploy-vs-package diff (tampered deployment copy).
Q = local_make_valid_package(run_root, 'case-n9', commit, tag, tree, pinned);
fid = fopen(fullfile(Q.deploy, 'mlsc_current_payload'), 'a');
assert(fid ~= -1, 'Tamper fixture failed.');
fwrite(fid, 'tampered');
fclose(fid);
local_expect_block(@() validate_mlsc_release('postinstall', ...
    'BuildManifest', Q.deploy_buildmat, 'ResourceManifest', Q.deploy_resmat, ...
    'ReleaseTag', tag, 'GateARecord', Q.record, 'DeployRoot', Q.deploy), 'deploy-vs-package');
fprintf('GATE-N9 PASS: deploy-vs-package diff blocks.\n');

% N10: missing Gate-A record.
Q = local_make_valid_package(run_root, 'case-n10', commit, tag, tree, pinned);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, ...
    'GateARecord', fullfile(run_root, 'case-n10', 'absent_gate_a.mat')), 'Gate-A');
fprintf('GATE-N10 PASS: missing Gate-A binding blocks.\n');

% N11: missing release identity.
Q = local_make_valid_package(run_root, 'case-n11', commit, tag, tree, pinned);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'GateARecord', Q.record), 'required');
fprintf('GATE-N11 PASS: missing release identity blocks.\n');

% N12: wrong expected fingerprint.
Q = local_make_valid_package(run_root, 'case-n12', commit, tag, tree, pinned);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, ...
    'ExpectedFingerprint', repmat('0', 1, 64), 'GateARecord', Q.record), 'expected fingerprint');
fprintf('GATE-N12 PASS: wrong expected fingerprint blocks.\n');

% N13: dirty-worktree reuse rejected (fail closed, never reused).
%   Synthetic throwaway repo only (never the real tree): a fresh
%   worktree is created pristine, but once dirtied the same worktree
%   must not be reused.
tmp_case = fullfile(run_root, 'case-n13');
mkdir(tmp_case);
tmp_repo = fullfile(tmp_case, 'repo');
mkdir(tmp_repo);
local_write(fullfile(tmp_repo, 'seed.txt'), 'seed');
assert(system(sprintf('git -C "%s" init -q 2>&1', tmp_repo)) == 0, 'Fixture git init failed.');
assert(system(sprintf('git -C "%s" add seed.txt 2>&1', tmp_repo)) == 0, 'Fixture git add failed.');
assert(system(sprintf('git -C "%s" -c user.name=fixture -c user.email=fixture@local commit -qm seed 2>&1', tmp_repo)) == 0, 'Fixture git commit failed.');
[s13, o13] = system(sprintf('git -C "%s" --no-pager rev-parse HEAD 2>&1', tmp_repo));
commit13 = lower(strtrim(o13));
assert(s13 == 0 && length(commit13) == 40, 'Fixture commit unresolvable.');
wt13 = mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13probe');
assert(exist(wt13, 'dir') == 7, 'Fresh fixture worktree missing.');
fid = fopen(fullfile(wt13, 'seed.txt'), 'a');
assert(fid ~= -1, 'Worktree dirtying failed.');
fwrite(fid, 'dirty');
fclose(fid);
local_expect_block(@() mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13probe'), 'not pristine');
fprintf('GATE-N13 PASS: dirty-worktree reuse rejected.\n');
system(sprintf('git -C "%s" --no-pager worktree remove --force "%s" 2>&1', tmp_repo, wt13));

% N13b: anchor-guard regression (strict top-level equality; synthetic
%   throwaway repo only, never the real tree). Covers the exact bypass
%   (candidate under the clean parent at the release commit with a
%   bogus .git entry plus conflicting GIT_DIR/GIT_WORK_TREE overrides
%   => REJECT as unverifiable), the accept-cases (pristine linked
%   worktree with .git file form, pristine standalone checkout with
%   .git directory form), and the reject-cases (plain subdirectory,
%   invalid metadata, wrong commit).
%   N13b-i EXACT BYPASS: the bogus .git file satisfies the old
%   existence check, and the conflicting overrides make unsanitized
%   git report the parent's pristine release state; the controlled
%   top-level lookup strips the overrides and fails on the bogus
%   entry, so reuse is refused instead of compiling attacker content
%   as the release source.
bypass13 = fullfile(tmp_repo, 'scratch', 'release_gate', 'worktree-n13bypass');
mkdir(bypass13);
local_write(fullfile(bypass13, '.git'), 'bogus');
old_git_dir = getenv('GIT_DIR');
old_git_wt = getenv('GIT_WORK_TREE');
setenv('GIT_DIR', fullfile(tmp_repo, '.git'));
setenv('GIT_WORK_TREE', tmp_repo);
n13b_ok = false;
n13b_me = [];
try
    local_expect_block(@() mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13bypass'), 'unverifiable');
    fprintf('GATE-N13B-BYPASS PASS: bogus anchor under clean parent rejected despite env overrides.\n');
    % Controlled-env positive control: the same conflicting overrides
    % must not break a legitimate pristine worktree (the sanitized
    % anchor still recognizes its own top level).
    wt_env = mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13envok');
    wt_env2 = mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13envok');
    assert(strcmp(wt_env, wt_env2) && exist(wt_env, 'dir') == 7, 'Pristine worktree rejected under env overrides.');
    fprintf('GATE-N13B-ENVOK PASS: pristine worktree accepted despite env overrides.\n');
    n13b_ok = true;
catch ME
    n13b_me = ME;
end
if isempty(old_git_dir)
    unsetenv('GIT_DIR');
else
    setenv('GIT_DIR', old_git_dir);
end
if isempty(old_git_wt)
    unsetenv('GIT_WORK_TREE');
else
    setenv('GIT_WORK_TREE', old_git_wt);
end
if ~n13b_ok
    if isempty(n13b_me)
        error('pseudo_CT:MLSCReleaseGate', 'N13b bypass fixture did not complete.');
    end
    rethrow(n13b_me);
end
% N13b-ii REJECT plain subdirectory (no .git entry): git discovery
%   would report the parent, so equality refuses it as unverifiable.
plain13 = fullfile(tmp_repo, 'scratch', 'release_gate', 'worktree-n13plain');
mkdir(plain13);
local_expect_block(@() mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13plain'), 'unverifiable');
fprintf('GATE-N13B-SUBDIR PASS: plain subdirectory refused.\n');
% N13b-iii REJECT invalid metadata (garbage .git file): the
%   controlled top-level lookup fails, so reuse is unverifiable.
invalid13 = fullfile(tmp_repo, 'scratch', 'release_gate', 'worktree-n13invalid');
mkdir(invalid13);
local_write(fullfile(invalid13, '.git'), 'definitely-not-a-gitlink');
local_expect_block(@() mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13invalid'), 'unverifiable');
fprintf('GATE-N13B-INVALID PASS: invalid git metadata refused.\n');
% N13b-iv REJECT wrong commit (existing pin check stays): the
%   pristine worktree pins the release commit, so any other commit
%   must not reuse it.
wrong13 = lower(strtrim(commit13));
if wrong13(1) ~= 'a'
    wrong13(1) = 'a';
else
    wrong13(1) = 'b';
end
local_expect_block(@() mlsc_release_gate('ensure_worktree', tmp_repo, wrong13, 'n13envok'), 'pins another source');
fprintf('GATE-N13B-WRONGCOMMIT PASS: wrong-commit reuse rejected.\n');
% N13b-v ACCEPT linked worktree (.git file form): fresh creation
%   followed by pristine reuse returns the same path.
wt_link = mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13link');
wt_link2 = mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13link');
assert(strcmp(wt_link, wt_link2) && exist(wt_link, 'dir') == 7, 'Linked-worktree reuse failed.');
assert(exist(fullfile(wt_link, '.git'), 'file') == 2, 'Linked worktree lacks the .git file form.');
fprintf('GATE-N13B-WORKTREE PASS: pristine linked worktree accepted.\n');
% N13b-vi ACCEPT standalone checkout (.git directory form): a clean
%   clone placed at the candidate path reuses successfully.
clone13 = fullfile(tmp_repo, 'scratch', 'release_gate', 'worktree-n13clone');
assert(system(sprintf('git clone -q "%s" "%s" 2>&1', tmp_repo, clone13)) == 0, 'Standalone clone fixture failed.');
assert(exist(fullfile(clone13, '.git'), 'dir') == 7, 'Standalone fixture lacks the .git directory form.');
wt_clone = mlsc_release_gate('ensure_worktree', tmp_repo, commit13, 'n13clone');
assert(strcmp(wt_clone, clone13), 'Standalone checkout reuse failed.');
fprintf('GATE-N13B-STANDALONE PASS: pristine standalone checkout accepted.\n');
system(sprintf('git -C "%s" --no-pager worktree remove --force "%s" 2>&1', tmp_repo, wt_link));
system(sprintf('git -C "%s" --no-pager worktree remove --force "%s" 2>&1', tmp_repo, wt_env));

% N14: unavailable release tree propagates (no recorded-only accept).
%   The manifest is recorded for a commit whose tree no repository can
%   fingerprint; the recompute failure must block, never fall back to
%   recorded evidence (which alone would accept this candidate).
fake_commit = repmat('c', 1, 40);
fake_tree = repmat('d', 1, 40);
F = local_make_valid_package(run_root, 'case-n14', fake_commit, tag, fake_tree, pinned);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', F.pkg, 'ReleaseCommit', fake_commit, ...
    'GateARecord', F.record), 'tree is unavailable');
fprintf('GATE-N14 PASS: unavailable-tree failure propagates.\n');

% N15: incomplete Gate-A rejected (missing runtime binding fields).
Q = local_make_valid_package(run_root, 'case-n15', commit, tag, tree, pinned);
loaded = load(Q.record);
gate_a = loaded.gate_a;
gate_a = rmfield(gate_a, 'mcr_root');
save(Q.record, 'gate_a');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'missing field');
fprintf('GATE-N15 PASS: incomplete Gate-A rejected.\n');

% N15b: absent native evidence rejected (never skipped).
Q = local_make_valid_package(run_root, 'case-n15b', commit, tag, tree, pinned);
loaded = load(Q.record);
gate_a = loaded.gate_a;
gate_a.native_paths = {fullfile(run_root, 'case-n15b', 'absent_native.mexa64')};
save(Q.record, 'gate_a');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', Q.pkg, 'ReleaseTag', tag, 'GateARecord', Q.record), 'missing native evidence');
fprintf('GATE-N15B PASS: absent native evidence rejected.\n');

% N16: deployment-path mismatch rejected (nested staging is not the
%   pinned runtime layout: the launcher must sit at the DeployRoot).
Q = local_make_valid_package(run_root, 'case-n16', commit, tag, tree, pinned);
nested = fullfile(run_root, 'case-n16', 'deploy-nested');
[ok_n16, msg_n16] = copyfile(Q.pkg, nested);
assert(ok_n16, 'Nested deploy fixture failed: %s.', msg_n16);
local_expect_block(@() validate_mlsc_release('postinstall', ...
    'BuildManifest', fullfile(nested, 'mlsc_current_build.mat'), ...
    'ResourceManifest', fullfile(nested, 'mlsc_current_resources.mat'), ...
    'ReleaseTag', tag, 'GateARecord', Q.record, 'DeployRoot', nested), 'runtime layout');
fprintf('GATE-N16 PASS: nested deployment layout rejected.\n');

% N16b: manifests from outside the deployment root rejected (manifests
%   must sit alongside at the DeployRoot).
local_expect_block(@() validate_mlsc_release('postinstall', ...
    'BuildManifest', Q.buildmat, 'ResourceManifest', Q.deploy_resmat, ...
    'ReleaseTag', tag, 'GateARecord', Q.record, 'DeployRoot', Q.deploy), 'alongside');
fprintf('GATE-N16B PASS: foreign manifest paths rejected.\n');

fprintf('=== MLSC release-gate tests passed: 2 positive + 20 negative ===\n');
end

function P = local_make_valid_package(root_dir, case_name, commit, tag, tree, pinned)
case_root = fullfile(root_dir, case_name);
mkdir(case_root);
pkg = fullfile(case_root, 'package');
mkdir(pkg);
bd = fullfile(pkg, 'payload_build');
mkdir(bd);
runner = fullfile(bd, 'run_mlsc_current_payload.sh');
exe = fullfile(bd, 'mlsc_current_payload');
readme = fullfile(bd, 'readme.txt');
local_write(runner, ['#!/bin/sh' char(10) '# fixture runner ' case_name char(10)]);
local_write(exe, ['fixture-executable-bytes-' case_name]);
local_write(readme, ['fixture readme ' case_name]);
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
build.release_tag = tag;
build.release_commit = commit;
build.release_tree = tree;
build.packaged_files = pfiles;
build.packaged_checksums = psums;
build.packaged_files_fingerprint = pfp;
build.resource_fingerprint = res_sha;
build.executable_fingerprint = exe_sha;
build.compiler_identity = 'MATLAB Compiler 26.1 (R2026a)';
build.required_toolboxes = {'Image_Toolbox'; 'Statistics_Toolbox'; 'Compiler'};
buildmat = fullfile(pkg, 'mlsc_current_build.mat');
save(buildmat, 'build');
build_sha = local_sha_hex(buildmat);
native = fullfile(case_root, 'spm_sample_vol.mexa64');
local_write(native, ['fixture-native-' case_name]);
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
deploy = fullfile(case_root, 'deploy');
mkdir(deploy);
% Runtime layout is flat per the pinned profile: staged
% 'payload_build/<name>' deploys to '<name>' at the deployment root
% (launcher at root, manifests alongside; nested staging rejected).
for kk = 1:numel(pfiles)
    rel_here = pfiles{kk};
    deploy_rel = local_deploy_rel(rel_here);
    src_here = fullfile(pkg, strrep(rel_here, '/', filesep));
    dst_here = fullfile(deploy, strrep(deploy_rel, '/', filesep));
    [parent_here, ~, ~] = fileparts(dst_here);
    if exist(parent_here, 'dir') ~= 7
        mkdir(parent_here);
    end
    [ok_cp, msg_cp] = copyfile(src_here, dst_here);
    assert(ok_cp, 'Deploy fixture copy failed: %s.', msg_cp);
end
[ok_mb, msg_mb] = copyfile(buildmat, fullfile(deploy, 'mlsc_current_build.mat'));
assert(ok_mb, 'Deploy manifest copy failed: %s.', msg_mb);
[ok_mr, msg_mr] = copyfile(resmat, fullfile(deploy, 'mlsc_current_resources.mat'));
assert(ok_mr, 'Deploy manifest copy failed: %s.', msg_mr);
P = struct('pkg', pkg, 'buildmat', buildmat, 'resmat', resmat, ...
    'deploy_buildmat', fullfile(deploy, 'mlsc_current_build.mat'), ...
    'deploy_resmat', fullfile(deploy, 'mlsc_current_resources.mat'), ...
    'record', record, 'deploy', deploy, 'src_fp', src_fp);
end

function local_test_r2010b_exception(root_dir, fixture_root)
if isempty(fixture_root)
    fixture_root = fullfile(root_dir, 'scratch', 'release_gate');
end
run_root = fullfile(fixture_root, 'validator_r2010b_exception');
assert(exist(run_root, 'dir') ~= 7, ...
    'Focused fixture directory already exists; preserving existing scratch data.');
[ok_root, msg_root] = mkdir(run_root);
assert(ok_root, 'Cannot create focused fixture dir: %s.', msg_root);
cleanup_root = onCleanup(@() local_cleanup(run_root)); %#ok<NASGU>
[s_head, o_head] = system(sprintf('git -C "%s" --no-pager rev-parse HEAD 2>&1', root_dir));
commit = lower(strtrim(o_head));
assert(s_head == 0 && length(commit) == 40, 'Release-source commit fixture is unavailable.');
tree = mlsc_release_gate('release_tree', root_dir, commit);

% These fixtures copy the actual retained package and never execute the
% scientific binary. The available checkout is tagged v3.1.0 (no v3.1.1
% tag exists); the v3.1.1 pre-tag path binds to a caller-supplied resolvable
% source commit while preserving the original build provenance.
package = local_copy_compiled_package(root_dir, run_root, 'exact');
loaded_build = load(fullfile(root_dir, 'compiled', 'mlsc_current_build.mat'), 'build');
assert(~strcmpi(strtrim(loaded_build.build.source_commit), commit), ...
    'Pinned payload fixture no longer distinguishes artifact provenance from the release source.');
[accepted, is_exception] = validate_mlsc_release('prepublication', ...
    'PackageDir', package, ...
    'BuildManifest', fullfile(root_dir, 'compiled', 'mlsc_current_build.mat'), ...
    'ReleaseTag', 'v3.1.0', 'ReleaseCommit', commit, 'RepoRoot', root_dir);
assert(accepted && is_exception, 'Exact R2010b artifact was not accepted with an independently resolved release identity.');
fprintf('GATE-R2010B-EXACT PASS: exact retained artifact accepted with separate BuildManifest and without Gate-A.\n');

% Before v3.1.1 has a tag, only the exact target version plus an explicit,
% resolvable release commit may validate this exact retained package.
[accepted_pretag, is_exception_pretag] = validate_mlsc_release('prepublication', ...
    'PackageDir', package, ...
    'BuildManifest', fullfile(root_dir, 'compiled', 'mlsc_current_build.mat'), ...
    'ExpectedTargetVersion', 'v3.1.1', 'ReleaseCommit', commit, ...
    'RepoRoot', root_dir);
assert(accepted_pretag && is_exception_pretag, ...
    'Exact R2010b artifact was not accepted for the explicit v3.1.1 pre-tag target.');
fprintf('GATE-V311-PRETAG PASS: exact retained package accepted for v3.1.1 with caller-supplied commit.\n');

local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', package, 'ExpectedTargetVersion', 'v3.1.2', ...
    'ReleaseCommit', commit, 'RepoRoot', root_dir), ...
    'only for exact target v3.1.1');
fprintf('GATE-V311-PRETAG-VERSION PASS: arbitrary target version rejected.\n');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', package, 'ExpectedTargetVersion', 'v3.1.1', ...
    'ReleaseTag', 'v3.1.0', 'ReleaseCommit', commit, 'RepoRoot', root_dir), ...
    'use ReleaseTag when the release tag exists');
fprintf('GATE-V311-PRETAG-TAG-CONFLICT PASS: expected target cannot replace an existing tag.\n');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', package, 'ExpectedTargetVersion', 'v3.1.1', ...
    'RepoRoot', root_dir), 'requires an explicit ReleaseCommit');
fprintf('GATE-V311-PRETAG-MISSING-COMMIT PASS: missing commit rejected.\n');
unknown_commit = repmat('f', 1, 40);
[s_unknown, ~] = system(sprintf( ...
    'git -C "%s" --no-pager cat-file -e "%s^{commit}" 2>/dev/null', ...
    root_dir, unknown_commit));
assert(s_unknown ~= 0, 'Unknown-commit rejection fixture unexpectedly exists.');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', package, 'ExpectedTargetVersion', 'v3.1.1', ...
    'ReleaseCommit', unknown_commit, 'RepoRoot', root_dir), ...
    'tree is unavailable');
fprintf('GATE-V311-PRETAG-UNKNOWN-COMMIT PASS: unresolvable release commit rejected.\n');

% The tagless target argument cannot be used in postinstall; after the
% v3.1.0 tag, the same actual deployment must pass only with tag semantics.
deploy = local_stage_compiled_deployment(package, run_root, 'exact-v310-deploy');
deploy_build = fullfile(deploy, 'mlsc_current_build.mat');
deploy_resources = fullfile(deploy, 'mlsc_current_resources.mat');
local_expect_block(@() validate_mlsc_release('postinstall', ...
    'DeployRoot', deploy, 'BuildManifest', deploy_build, ...
    'ResourceManifest', deploy_resources, 'ExpectedTargetVersion', 'v3.1.1', ...
    'ReleaseCommit', commit, 'RepoRoot', root_dir), 'prepublication-only');
assert(validate_mlsc_release('postinstall', ...
    'DeployRoot', deploy, 'BuildManifest', deploy_build, ...
    'ResourceManifest', deploy_resources, 'ReleaseTag', 'v3.1.0', ...
    'ReleaseCommit', commit, 'RepoRoot', root_dir), ...
    'The exact R2010b deployment did not pass postinstall with the actual v3.1.0 tag.');
fprintf('GATE-R2010B-POSTINSTALL PASS: pre-tag target rejected; actual tag+commit accepted.\n');

% A future v3.1.1 tag, when present, must accept the same exact pinned bytes
% through the final actual ReleaseTag+ReleaseCommit route.
[s_v311, o_v311] = system(sprintf( ...
    'git -C "%s" --no-pager rev-parse --verify "refs/tags/v3.1.1^{commit}" 2>&1', ...
    root_dir));
if s_v311 == 0
    commit_v311 = lower(strtrim(o_v311));
    [accepted_v311, is_exception_v311] = validate_mlsc_release('prepublication', ...
        'PackageDir', package, ...
        'BuildManifest', fullfile(root_dir, 'compiled', 'mlsc_current_build.mat'), ...
        'ReleaseTag', 'v3.1.1', 'ReleaseCommit', commit_v311, 'RepoRoot', root_dir);
    assert(accepted_v311 && is_exception_v311, ...
        'Exact R2010b artifact was not accepted for the explicitly pinned v3.1.1 tag.');
    fprintf('GATE-V311-EXACT PASS: unchanged pinned R2010b payload accepted for v3.1.1.\n');
else
    fprintf('GATE-V311-EXACT SKIP: v3.1.1 tag is absent in this v3.1.0 checkout.\n');
end

% A real tag and a different, resolvable commit must still fail commit==tag.
[s_parent, o_parent] = system(sprintf( ...
    'git -C "%s" --no-pager rev-parse --verify "v3.1.0~1^{commit}" 2>&1', ...
    root_dir));
wrong_tag_commit = lower(strtrim(o_parent));
assert(s_parent == 0 && length(wrong_tag_commit) == 40, ...
    'Could not resolve a distinct prior commit for the tag-mismatch check.');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', package, 'ReleaseTag', 'v3.1.0', ...
    'ReleaseCommit', wrong_tag_commit, 'RepoRoot', root_dir), ...
    'does not match tag v3.1.0');
fprintf('GATE-R2010B-TAG-COMMIT-MISMATCH PASS: mismatched tag/commit rejected.\n');

% The exception is an explicit two-tag compatibility, not a version wildcard.
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', package, 'ReleaseTag', 'v3.1.2', 'RepoRoot', root_dir), ...
    'only release tags v3.1.0 or v3.1.1');
fprintf('GATE-R2010B-TAG-SCOPE PASS: unsupported release version rejected.\n');

% Supplying the anchored MAT separately must not bless a mismatched copy in
% the staged package; the package's own build manifest is part of the pin.
mismatched_manifest = local_copy_compiled_package(root_dir, run_root, ...
    'mismatched-build-manifest');
fid = fopen(fullfile(mismatched_manifest, 'mlsc_current_build.mat'), 'a');
assert(fid ~= -1, 'Could not tamper with the isolated build-manifest copy.');
fwrite(fid, '# tampered');
fclose(fid);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', mismatched_manifest, ...
    'BuildManifest', fullfile(root_dir, 'compiled', 'mlsc_current_build.mat'), ...
    'ExpectedTargetVersion', 'v3.1.1', 'ReleaseCommit', commit, ...
    'RepoRoot', root_dir), 'packaged build manifest');
fprintf('GATE-R2010B-BUILD-MANIFEST PASS: external anchored MAT cannot bless modified packaged MAT.\n');

missing_manifest = local_copy_compiled_package(root_dir, run_root, ...
    'missing-build-manifest');
delete(fullfile(missing_manifest, 'mlsc_current_build.mat'));
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', missing_manifest, ...
    'BuildManifest', fullfile(root_dir, 'compiled', 'mlsc_current_build.mat'), ...
    'ExpectedTargetVersion', 'v3.1.1', 'ReleaseCommit', commit, ...
    'RepoRoot', root_dir), 'packaged build manifest');
fprintf('GATE-R2010B-MISSING-BUILD-MANIFEST PASS: external anchored MAT cannot replace packaged MAT.\n');

tampered = local_copy_compiled_package(root_dir, run_root, 'tampered');
fid = fopen(fullfile(tampered, 'payload_build', 'mlsc_current_payload'), 'a');
assert(fid ~= -1, 'Could not tamper with the isolated scratch copy.');
fwrite(fid, '# tampered');
fclose(fid);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', tampered, 'ExpectedTargetVersion', 'v3.1.1', ...
    'ReleaseCommit', commit, 'RepoRoot', root_dir), 'executable');
fprintf('GATE-R2010B-TAMPER PASS: modified executable bytes rejected.\n');

missing = local_copy_compiled_package(root_dir, run_root, 'missing');
delete(fullfile(missing, 'payload_build', 'mccExcludedFiles.log'));
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', missing, 'ExpectedTargetVersion', 'v3.1.1', ...
    'ReleaseCommit', commit, 'RepoRoot', root_dir), ...
    'mccExcludedFiles.log is missing');
fprintf('GATE-R2010B-MISSING PASS: missing inventoried payload rejected.\n');

% Reuse the established R2026a fixture to prove the normal path still
% reaches its strict runtime gate instead of entering the exception. The
% currently pinned host MCR is R2010b, so this R2026a control is expected to
% block there. Its toy executable is never run or scientific-binary proof.
pinned = mlsc_current_validate('pinned_mcr_root');
strict = local_make_valid_package(run_root, 'normal-strict', commit, '', tree, pinned);
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', strict.pkg, 'ExpectedTargetVersion', 'v3.1.1', ...
    'ReleaseCommit', commit, 'GateARecord', strict.record, 'RepoRoot', root_dir), ...
    'only for the exact pinned R2010b artifact');
local_expect_block(@() validate_mlsc_release('prepublication', ...
    'PackageDir', strict.pkg, 'ReleaseCommit', commit, ...
    'GateARecord', strict.record, 'RepoRoot', root_dir), ...
    'Build release is incompatible');
fprintf('GATE-R2010B-STRICT PASS: R2026a candidate did not enter the exception and remained runtime-gated.\n');
end

function package = local_copy_compiled_package(root_dir, run_root, case_name)
case_root = fullfile(run_root, case_name);
mkdir(case_root);
package = fullfile(case_root, 'package');
mkdir(package);
source = fullfile(root_dir, 'compiled');
entries = dir(source);
for kk = 1:numel(entries)
    name = entries(kk).name;
    if strcmp(name, '.') || strcmp(name, '..')
        continue;
    end
    [ok_copy, msg_copy] = copyfile(fullfile(source, name), fullfile(package, name));
    assert(ok_copy, 'Could not copy retained package into scratch: %s.', msg_copy);
end
end

function deploy = local_stage_compiled_deployment(package, run_root, case_name)
case_root = fullfile(run_root, case_name);
mkdir(case_root);
deploy = fullfile(case_root, 'deploy');
mkdir(deploy);
loaded = load(fullfile(package, 'mlsc_current_build.mat'), 'build');
assert(isfield(loaded, 'build') && isfield(loaded.build, 'packaged_files'), ...
    'Retained build manifest has no package inventory.');
for kk = 1:numel(loaded.build.packaged_files)
    rel_here = loaded.build.packaged_files{kk};
    deploy_rel = local_deploy_rel(rel_here);
    src_here = fullfile(package, strrep(rel_here, '/', filesep));
    dst_here = fullfile(deploy, strrep(deploy_rel, '/', filesep));
    [parent_here, ~, ~] = fileparts(dst_here);
    if exist(parent_here, 'dir') ~= 7
        mkdir(parent_here);
    end
    [ok_copy, msg_copy] = copyfile(src_here, dst_here);
    assert(ok_copy, 'Retained package deployment staging failed: %s.', msg_copy);
end
for kk = 1:2
    if kk == 1
        name_here = 'mlsc_current_build.mat';
    else
        name_here = 'mlsc_current_resources.mat';
    end
    [ok_copy, msg_copy] = copyfile(fullfile(package, name_here), ...
        fullfile(deploy, name_here));
    assert(ok_copy, 'Retained package manifest staging failed: %s.', msg_copy);
end
end

function mapped = local_deploy_rel(rel_here)
% Staged 'payload_build/<name>' deploys flat to '<name>' (pinned runtime
% layout: launcher at the deployment root, manifests alongside).
mapped = rel_here;
prefix = 'payload_build/';
if strncmp(rel_here, prefix, length(prefix))
    mapped = rel_here(length(prefix) + 1:end);
end
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
assert(failed, 'Fail-closed gate did not reject.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCReleaseGate'), 'Unexpected failure identifier: %s.', actual_id);
assert(~isempty(strfind(actual_msg, reason_substr)), 'Gate reason missing "%s": %s.', reason_substr, actual_msg);
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
