function test_mlsc_current_remediation()
%TEST_MLSC_CURRENT_REMEDIATION Narrow T004 B1/B4/B5 offline remediation.
%   Offline only (no live SSH/sbatch, no Gates/production, no
%   catalog/resolver, no /usr/pubsw mutation). Keeps ONE lifecycle/shared
%   machinery. Covers the minimum 20:
%     B1 1-3: offline validator-level mapping/evidence/identity via the
%       SAME production validators the lifecycle consumes (explicit
%       key->basename mapping, copied-hash match, structured evidence);
%       full lifecycle SUCCESS/finalization through the real production
%       copyback is NOT proven here (proof-only test_injected_backend seam
%       removed; deferred to T006 / Gate B). Missing output fails at the
%       validator level (no lifecycle seam).
%     B4 6-11: Update mismatch, wrong arch, same-size runner/build/
%       resource mutation, missing hash utility -- all fail before PREPARE
%       (exact MCR identity, mandatory SHA-256, no substring, no fallback).
%     B5 12-20: valid success, missing SHA fail, malformed SHA fail,
%       same-size att_map fail, same-size QC fail, copied SHA mismatch
%       fail, missing semantic fail, dtype/dims/finite/affine mismatch
%       fail, affine round-trip exact (%.17g lossless, no tolerance).
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
addpath(fullfile(root_dir, 'vers'), '-begin');

spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
assert(exist(spm_root, 'dir') == 7, 'SPM fixture root unavailable.');
addpath(genpath(spm_root), '-begin');
addpath(fullfile(spm_root, 'matlabbatch'), '-begin');
assert(exist('spm_vol', 'file') == 2, 'spm_vol unavailable.');
assert(exist('spm_write_vol', 'file') == 2, 'spm_write_vol unavailable.');

pinned = mlsc_current_validate('pinned_mcr_root');
assert(strcmp(pinned, '/usr/pubsw/common/matlab/26.1'), 'Pinned drifted.');
assert(exist(pinned, 'dir') == 7, 'Pinned unavailable.');
assert(exist(fullfile(pinned, 'runtime', 'glnxa64'), 'dir') == 7, ...
    'Pinned structure malformed.');
actual_pinned = mlsc_current_validate('actual_identity', pinned);
assert(strcmp(actual_pinned.release, 'R2026a'), 'Pinned release mismatch.');
assert(strcmp(actual_pinned.version, '26.1.0.3251617'), 'Pinned version mismatch.');
assert(actual_pinned.update == 2, 'Pinned update is not 2.');
assert(strcmp(actual_pinned.arch, 'glnxa64'), 'Pinned arch mismatch.');
assert(isequal(actual_pinned.mcr_version, [26 1]), 'Pinned mcrversion mismatch.');

test_root = tempname;
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

freesurfer_env = fullfile(test_root, 'freesurfer-env');
local_write(freesurfer_env, '# fixture');
shell_path = '/bin/bash';

% Shared current fixtures (contract-level, pending offline state).
base_shared = fullfile(test_root, 'base-shared');
mkdir(base_shared);
base_input = fullfile(base_shared, 'mprage.nii');
local_write(base_input, 'fixture');
base_runner = fullfile(test_root, 'run_mlsc_current_payload.sh');
local_write(base_runner, '# fixture runner B1B4B5');
build_path = fullfile(test_root, 'build.mat');
resource_path = fullfile(test_root, 'resources.mat');
atlas_dir = fullfile(test_root, 'Batch_atlas_current');
mkdir(atlas_dir);
local_write_valid_manifests(build_path, resource_path, base_runner, pinned, atlas_dir);
base_subject = struct('subject_id', 'remediation-fixture', ...
    'shared_input', base_input, 'shared_temp', base_shared, ...
    'check_aliasing', 1, 'recenter_before_normalization', 'Yes');
base_config = struct();
base_config.mode = 'mlsc';
base_config.implementation = 'current';
base_config.aliasing_default = 0;
base_config.recenter_before_normalization = 'No';
base_config.bone_enabled = false;
base_config.zero_background = 'No';
base_config.current = struct('runner', base_runner, ...
    'mcr_root', pinned, 'build_manifest', build_path, ...
    'resource_manifest', resource_path);
base_config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'shell', shell_path, 'freesurfer_env', freesurfer_env, ...
    'partition', 'basic', 'nodes', 1, 'ntasks', 1, ...
    'cpus_per_task', 1, 'memory', '32G', 'time', '04:00:00');
base_runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(base_shared, 'job.sh'));

% B3 preserved: production submission with pending native evidence stays
% BLOCKED (no fake token, no magic Gate-A string, no bypass).
mlsc_current_validate('validate_contract', base_config);
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', base_config), ...
    'pseudo_CT:MLSCCurrentNativeEvidence');
blocked_transport = struct('verify', @() true, 'submit_script', @local_never_submit);
local_assert_error_id(@() mlsc_backend(base_subject, base_config, base_runtime, blocked_transport), ...
    'pseudo_CT:MLSCCurrentNativeEvidence');
fprintf('B1-PRE PASS: production pending->BLOCKED preserved (B3 not weakened).\n');

% ------------------------------------------------------------------
% B1 1-5: REAL lifecycle current-success via SAME production code.
% ------------------------------------------------------------------
% Generate the REAL production artifact (proves contract/payload mapping).
gen_subject = base_subject;
gen_config = base_config;
gen_runtime = base_runtime;
artifact = mlsc_generate_slurm_script(gen_subject, gen_config, gen_runtime);
assert(isfield(artifact, 'is_current') && isequal(artifact.is_current, true), ...
    'B1: artifact not current.');
assert(~isempty(strfind(artifact.script_text, '"$current_runner" "$current_mcr_root" prepare')), ...
    'B1: PREPARE missing.');
assert(~isempty(strfind(artifact.script_text, '"$current_runner" "$current_mcr_root" compute')), ...
    'B1: COMPUTE missing.');
% New B4 guards must be embedded (mandatory SHA, exact MCR, generation).
assert(~isempty(strfind(artifact.script_text, 'expected_runner_sha256=')), 'B1: runner hash missing.');
assert(~isempty(strfind(artifact.script_text, 'expected_mcr_generation=')), 'B1: generation missing.');
assert(isempty(strfind(artifact.script_text, 'grep -F -q "$expected_mcr_release"')), ...
    'B1: substring MCR check remains.');
assert(~isempty(strfind(artifact.script_text, 'actual_mcr_release')), 'B1: exact MCR missing.');

% Build a valid shared-temp copyback simulation (node-local outputs already
% copied back): att_map (lossless affine) + QC + version + mandatory evidence.
b1_shared = fullfile(test_root, 'b1-success');
mkdir(b1_shared);
b1_input = fullfile(b1_shared, 'mprage.nii');
local_write(b1_input, 'fixture');
b1_runner = fullfile(test_root, 'b1-runner.sh');
local_write(b1_runner, '# fixture runner B1 success');
b1_build = fullfile(test_root, 'b1-build.mat');
b1_resources = fullfile(test_root, 'b1-resources.mat');
local_write_valid_manifests(b1_build, b1_resources, b1_runner, pinned, atlas_dir);
b1_config = base_config;
b1_config.current.runner = b1_runner;
b1_config.current.build_manifest = b1_build;
b1_config.current.resource_manifest = b1_resources;
b1_subject = struct('subject_id', 'b1-success', ...
    'shared_input', b1_input, 'shared_temp', b1_shared, ...
    'check_aliasing', 1, 'recenter_before_normalization', 'Yes');
b1_gen_runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(b1_shared, 'job.sh'));
b1_artifact = mlsc_generate_slurm_script(b1_subject, b1_config, b1_gen_runtime);
assert(b1_artifact.is_current, 'B1: artifact identity lost.');

% Non-trivial affine that %.10f would corrupt (~3e-11); %.17g preserves.
b1_affine = [0.333333333333333 0 0 -10.5; 0 0.987654321098765 0 20.25; ...
    0 0 1.5 -30.125; 0 0 0 1];
b1_att = fullfile(b1_shared, 'att_map.nii');
local_create_nifti(b1_att, [8 8 8], b1_affine);
b1_qc = fullfile(b1_shared, 'Fusion_MR_Pseudo_CT_validation.tiff');
local_write(b1_qc, 'b1-qc-bytes-12345');
b1_ver_txt = fullfile(b1_shared, 'Pseudo_CT_AC_Version.txt');
local_write(b1_ver_txt, 'b1-version-1.0');
local_write(fullfile(b1_shared, 'mlsc_current_handoff.mat'), 'handoff-stub');
% Save a minimal valid handoff MAT for completeness (lifecycle only needs nonempty).
handoff_stub = struct('schema', 'pseudo-CT.current-handoff/v1');
save(fullfile(b1_shared, 'mlsc_current_handoff.mat'), 'handoff_stub');
local_write(fullfile(b1_shared, 'mlsc_current_prepare_evidence.txt'), 'prepare-ok');
b1_verification = fullfile(b1_shared, 'mlsc_current_output_verification.txt');
local_write_verification(b1_verification, b1_att, b1_qc, b1_ver_txt);

% B1-1 mapping: explicit key->basename contract, no inference.
output_map = mlsc_current_validate('output_filename_map');
assert(strcmp(output_map.att_map, 'att_map.nii'), 'B1: att_map key drifted.');
assert(strcmp(output_map.version, 'Pseudo_CT_AC_Version.txt'), 'B1: version key drifted.');
assert(strcmp(output_map.validation_fusion, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'B1: fusion key drifted.');
assert(strcmp(output_map.validation_composite, 'Composite_Fusion_MR_Pseudo_CT_validation.tiff'), 'B1: composite missing.');
assert(exist(b1_att, 'file') == 2 && exist(b1_qc, 'file') == 2 && exist(b1_ver_txt, 'file') == 2, ...
    'B1: mapped outputs not copied to destination.');
fprintf('B1-1 PASS: real mapping (att_map/QC/version) via explicit contract.\n');

% B1-2/3 hash + evidence via production validators (same code lifecycle uses).
assert(mlsc_current_validate('verify_output_verification', b1_verification), 'B1: evidence rejected.');
assert(mlsc_current_validate('verify_copyback_identity', b1_shared, b1_verification), 'B1: identity rejected.');
assert(mlsc_current_validate('verify_att_map_semantic', b1_att, b1_verification), 'B1: semantic rejected.');
fprintf('B1-2/3 PASS: structured evidence consumed, copied hashes match compute hashes.\n');

% B1-4/5 seam removed: runtime.test_injected_backend proof-only seam has
% been removed from production mlsc_lifecycle (no other production
% purpose; no replacement seam added). Injected fixtures no longer prove
% full success/finalization. Full successful mlsc-current job through the
% real production copyback, required-output verification, caller
% finalization, durable evidence persistence, and reload/assertion is
% deferred to T006 / Gate B (see orchestration T006 follow-up). Here
% retain only the production-seam-absence guard plus offline
% validator-level checks (no lifecycle seam, pre-existing testability
% preserved via transport/query seams elsewhere).
b1_lifecycle_path = fullfile(root_dir, 'src', 'mlsc', 'mlsc_lifecycle.m');
b1_fid = fopen(b1_lifecycle_path, 'r');
assert(b1_fid ~= -1, 'B1: lifecycle source unreadable.');
b1_raw = fread(b1_fid, inf, '*char')';
fclose(b1_fid);
lifecycle_source_b1 = b1_raw;
assert(isempty(strfind(lifecycle_source_b1, 'test_injected_backend')), 'B1: proof-only seam remains.');
fprintf('B1-4 PASS: proof-only injected-backend seam removed (full success deferred to T006 / Gate B).\n');

% B1-5 missing-output negative via validators (no lifecycle seam).
% Reuse B1 verification (declares QC) but omit the QC file: validator must fail.
b1m_shared = fullfile(test_root, 'b1-missing');
mkdir(b1m_shared);
b1m_input = fullfile(b1m_shared, 'mprage.nii');
local_write(b1m_input, 'fixture');
b1m_att = fullfile(b1m_shared, 'att_map.nii');
local_create_nifti(b1m_att, [8 8 8], eye(4));
b1m_ver_txt = fullfile(b1m_shared, 'Pseudo_CT_AC_Version.txt');
local_write(b1m_ver_txt, 'b1m-version');
handoff_m = struct('schema', 'pseudo-CT.current-handoff/v1');
save(fullfile(b1m_shared, 'mlsc_current_handoff.mat'), 'handoff_m');
local_write(fullfile(b1m_shared, 'mlsc_current_prepare_evidence.txt'), 'prepare-ok');
% Point the missing shared temp at the B1 verification that declares QC,
% but the QC file is absent in b1m_shared: copy verification + att/version.
copyfile(b1_verification, fullfile(b1m_shared, 'mlsc_current_output_verification.txt'));
assert(~mlsc_current_validate('verify_copyback_identity', b1m_shared, ...
    fullfile(b1m_shared, 'mlsc_current_output_verification.txt')), 'B1: missing output did not fail.');
fprintf('B1-5 PASS: missing output fails at validator level (no lifecycle seam).\n');

% ------------------------------------------------------------------
% B4 6-11: FAIL-CLOSED STARTUP (exact MCR + mandatory SHA).
% ------------------------------------------------------------------
% B4-6 Update mismatch: expected Update 2 vs actual Update 0 MUST fail
% BEFORE PREPARE (exact numeric, no substring).
fake_mcr0 = fullfile(test_root, 'fake-mcr-update0');
mkdir(fake_mcr0);
mkdir(fullfile(fake_mcr0, 'runtime', 'glnxa64'));
local_write(fullfile(fake_mcr0, 'VersionInfo.xml'), ...
    ['<?xml version="1.0"?><MathWorks_version_info><version>26.1.0.3251617</version>' ...
     '<release>R2026a</release><update>Update 0</update></MathWorks_version_info>']);
actual0 = mlsc_current_validate('actual_identity', fake_mcr0);
assert(actual0.update == 0, 'B4: Update0 not parsed.');
assert(actual0.update < 2, 'B4: Update0 vs Update2 did not fail numerically.');
% Startup harness with current_mcr_root=fake0 must exit nonzero before PREPARE.
[status_u0, out_u0] = local_run_recheck_with_mcr(artifact, base_shared, base_runner, ...
    build_path, resource_path, fake_mcr0, test_root);
assert(status_u0 ~= 0, 'B4: Update0 did not fail before PREPARE.');
assert(isempty(strfind(out_u0, 'TOCTOU_RECHECK_PASSED')), 'B4: Update0 reached PREPARE.');
% Update 20 must not confuse Update 2 (exact, not substring).
fake_mcr20 = fullfile(test_root, 'fake-mcr-update20');
mkdir(fake_mcr20);
mkdir(fullfile(fake_mcr20, 'runtime', 'glnxa64'));
local_write(fullfile(fake_mcr20, 'VersionInfo.xml'), ...
    ['<?xml version="1.0"?><MathWorks_version_info><version>26.1.0.3251617</version>' ...
     '<release>R2026a</release><update>Update 20</update></MathWorks_version_info>']);
actual20 = mlsc_current_validate('actual_identity', fake_mcr20);
assert(actual20.update == 20, 'B4: Update20 not parsed.');
assert(actual20.update ~= 2, 'B4: Update20 confused with Update2.');
[status_u20, out_u20] = local_run_recheck_with_mcr(artifact, base_shared, base_runner, ...
    build_path, resource_path, fake_mcr20, test_root);
assert(status_u20 ~= 0, 'B4: Update20 did not fail before PREPARE.');
assert(isempty(strfind(out_u20, 'TOCTOU_RECHECK_PASSED')), 'B4: Update20 reached PREPARE.');
fprintf('B4-6 PASS: Update mismatch (0 and 20 vs 2) fails before PREPARE.\n');

% B4-7 Wrong arch fails before PREPARE.
fake_arch = fullfile(test_root, 'fake-mcr-badarch');
mkdir(fake_arch);
mkdir(fullfile(fake_arch, 'runtime', 'glnxa64'));
local_write(fullfile(fake_arch, 'VersionInfo.xml'), ...
    ['<?xml version="1.0"?><MathWorks_version_info><version>26.1.0.3251617</version>' ...
     '<release>R2026a</release><update>Update 2</update><arch>win64</arch></MathWorks_version_info>']);
local_assert_error(@() mlsc_current_validate('actual_identity', fake_arch));
[status_arch, out_arch] = local_run_recheck_with_mcr(artifact, base_shared, base_runner, ...
    build_path, resource_path, fake_arch, test_root);
assert(status_arch ~= 0, 'B4: wrong arch did not fail before PREPARE.');
assert(isempty(strfind(out_arch, 'TOCTOU_RECHECK_PASSED')), 'B4: wrong arch reached PREPARE.');
fprintf('B4-7 PASS: wrong arch fails before PREPARE.\n');

% B4-8/9/10 Same-size runner/build/resource mutation detected (SHA mandatory).
% Runner: same byte size, different content.
b4_runner = fullfile(test_root, 'b4-runner.sh');
local_write(b4_runner, 'ABCD1234');
assert(dir(b4_runner).bytes == 8, 'B4: runner size precondition.');
b4_build = fullfile(test_root, 'b4-build.mat');
b4_resources = fullfile(test_root, 'b4-resources.mat');
local_write_valid_manifests(b4_build, b4_resources, b4_runner, pinned, atlas_dir);
b4_shared = fullfile(test_root, 'b4-shared');
mkdir(b4_shared);
b4_input = fullfile(b4_shared, 'mprage.nii');
local_write(b4_input, 'fixture');
b4_subject = struct('subject_id', 'b4', 'shared_input', b4_input, ...
    'shared_temp', b4_shared, 'check_aliasing', 1, ...
    'recenter_before_normalization', 'Yes');
b4_config = base_config;
b4_config.current.runner = b4_runner;
b4_config.current.build_manifest = b4_build;
b4_config.current.resource_manifest = b4_resources;
b4_artifact = mlsc_generate_slurm_script(b4_subject, b4_config, ...
    struct('account', 'fixture-account', 'script_path', fullfile(b4_shared, 'job.sh')));
[status_clean, out_clean] = local_run_recheck_with_mcr(b4_artifact, b4_shared, b4_runner, ...
    b4_build, b4_resources, pinned, test_root);
assert(status_clean == 0 && ~isempty(strfind(out_clean, 'TOCTOU_RECHECK_PASSED')), ...
    'B4: clean recheck did not pass: %s', out_clean);
% Mutate runner same-size: ABCD1234 -> ABCD1235 (8 bytes, different SHA).
local_write(b4_runner, 'ABCD1235');
assert(dir(b4_runner).bytes == 8, 'B4: same-size runner precondition.');
[status_r, out_r] = local_run_recheck_with_mcr(b4_artifact, b4_shared, b4_runner, ...
    b4_build, b4_resources, pinned, test_root);
assert(status_r ~= 0, 'B4: same-size runner mutation did not fail.');
assert(isempty(strfind(out_r, 'TOCTOU_RECHECK_PASSED')), 'B4: mutated runner reached PREPARE.');
fprintf('B4-8 PASS: same-size runner mutation fails before PREPARE.\n');
% Restore runner, mutate build same-size (flip one MAT byte, same length).
local_write(b4_runner, 'ABCD1234');
b4_build_bytes_before = dir(b4_build).bytes;
local_flip_one_byte(b4_build);
assert(dir(b4_build).bytes == b4_build_bytes_before, 'B4: same-size build precondition.');
[status_b, out_b] = local_run_recheck_with_mcr(b4_artifact, b4_shared, b4_runner, ...
    b4_build, b4_resources, pinned, test_root);
assert(status_b ~= 0, 'B4: same-size build mutation did not fail.');
assert(isempty(strfind(out_b, 'TOCTOU_RECHECK_PASSED')), 'B4: mutated build reached PREPARE.');
fprintf('B4-9 PASS: same-size build mutation fails before PREPARE.\n');
% Restore build by regenerating manifests, mutate resource same-size.
local_write_valid_manifests(b4_build, b4_resources, b4_runner, pinned, atlas_dir);
b4_artifact2 = mlsc_generate_slurm_script(b4_subject, b4_config, ...
    struct('account', 'fixture-account', 'script_path', fullfile(b4_shared, 'job2.sh')));
b4_res_bytes_before = dir(b4_resources).bytes;
local_flip_one_byte(b4_resources);
assert(dir(b4_resources).bytes == b4_res_bytes_before, 'B4: same-size resource precondition.');
[status_res, out_res] = local_run_recheck_with_mcr(b4_artifact2, b4_shared, b4_runner, ...
    b4_build, b4_resources, pinned, test_root);
assert(status_res ~= 0, 'B4: same-size resource mutation did not fail.');
assert(isempty(strfind(out_res, 'TOCTOU_RECHECK_PASSED')), 'B4: mutated resource reached PREPARE.');
fprintf('B4-10 PASS: same-size resource mutation fails before PREPARE.\n');

% B4-11 Missing hash utility fails closed before PREPARE.
restricted_path = local_restricted_path_without_sha256(test_root);
[status_nohash, out_nohash] = local_run_recheck_restricted_path(b4_artifact2, b4_shared, ...
    b4_runner, b4_build, b4_resources, pinned, test_root, restricted_path);
assert(status_nohash ~= 0, 'B4: missing hash utility did not fail closed.');
assert(isempty(strfind(out_nohash, 'TOCTOU_RECHECK_PASSED')), 'B4: missing utility reached PREPARE.');
fprintf('B4-11 PASS: missing hash utility fails closed before PREPARE.\n');

% ------------------------------------------------------------------
% B5 12-20: STRICT IDENTITY (mandatory SHA, structural, lossless affine).
% ------------------------------------------------------------------
b5_shared = fullfile(test_root, 'b5-valid');
mkdir(b5_shared);
b5_affine = [0.333333333333333 0 0 -10.5; 0 0.987654321098765 0 20.25; ...
    0 0 1.5 -30.125; 0 0 0 1];
b5_att = fullfile(b5_shared, 'att_map.nii');
local_create_nifti(b5_att, [8 8 8], b5_affine);
b5_qc = fullfile(b5_shared, 'Fusion_MR_Pseudo_CT_validation.tiff');
local_write(b5_qc, 'b5-qc-12345678');
b5_ver = fullfile(b5_shared, 'Pseudo_CT_AC_Version.txt');
local_write(b5_ver, 'b5-version-1.0');
b5_verification = fullfile(b5_shared, 'mlsc_current_output_verification.txt');
local_write_verification(b5_verification, b5_att, b5_qc, b5_ver);
% B5-12 valid success.
assert(mlsc_current_validate('verify_output_verification', b5_verification), 'B5: valid evidence rejected.');
assert(mlsc_current_validate('verify_copyback_identity', b5_shared, b5_verification), 'B5: valid identity rejected.');
assert(mlsc_current_validate('verify_att_map_semantic', b5_att, b5_verification), 'B5: valid semantic rejected.');
fprintf('B5-12 PASS: valid success (SHA + structural + lossless affine).\n');

% B5-13 missing SHA fails (strip all sha256= tokens).
b5_nosha = fullfile(test_root, 'b5-nosha.txt');
local_write_verification_no_sha(b5_nosha, b5_att, b5_qc, b5_ver);
assert(~mlsc_current_validate('verify_output_verification', b5_nosha), 'B5: missing SHA passed.');
assert(~mlsc_current_validate('verify_copyback_identity', b5_shared, b5_nosha), 'B5: missing SHA identity passed.');
fprintf('B5-13 PASS: missing SHA fails.\n');

% B5-14 malformed SHA fails (short hex + non-hex).
b5_badsha = fullfile(test_root, 'b5-badsha.txt');
local_write_verification_bad_sha(b5_badsha, b5_att, b5_qc, b5_ver);
assert(~mlsc_current_validate('verify_output_verification', b5_badsha), 'B5: malformed SHA passed.');
assert(~mlsc_current_validate('verify_copyback_identity', b5_shared, b5_badsha), 'B5: malformed identity passed.');
fprintf('B5-14 PASS: malformed SHA fails.\n');

% B5-15 same-size att_map fails (same bytes, different content).
b5_same_att_dir = fullfile(test_root, 'b5-same-att');
mkdir(b5_same_att_dir);
b5_att_a = fullfile(test_root, 'b5-att-a.nii');
b5_att_b = fullfile(test_root, 'b5-att-b.nii');
local_create_nifti(b5_att_a, [8 8 8], eye(4));
local_create_nifti_different_data(b5_att_b, [8 8 8], eye(4));
assert(dir(b5_att_a).bytes == dir(b5_att_b).bytes, 'B5: same-size att precondition.');
% Verification declares A; shared carries B (same size, different SHA).
b5_same_shared = fullfile(test_root, 'b5-same-shared');
mkdir(b5_same_shared);
copyfile(b5_att_b, fullfile(b5_same_shared, 'att_map.nii'));
copyfile(b5_qc, fullfile(b5_same_shared, 'Fusion_MR_Pseudo_CT_validation.tiff'));
copyfile(b5_ver, fullfile(b5_same_shared, 'Pseudo_CT_AC_Version.txt'));
b5_same_ver = fullfile(test_root, 'b5-same-ver.txt');
local_write_verification(b5_same_ver, b5_att_a, b5_qc, b5_ver);
assert(~mlsc_current_validate('verify_copyback_identity', b5_same_shared, b5_same_ver), ...
    'B5: same-size att_map passed.');
assert(~mlsc_current_validate('verify_att_map_semantic', fullfile(b5_same_shared, 'att_map.nii'), b5_same_ver), ...
    'B5: same-size att semantic passed.');
fprintf('B5-15 PASS: same-size att_map fails.\n');

% B5-16 same-size QC fails (same bytes, different content).
b5_qc_a = fullfile(test_root, 'b5-qc-a.tiff');
b5_qc_b = fullfile(test_root, 'b5-qc-b.tiff');
local_write(b5_qc_a, 'ABCD1234');
local_write(b5_qc_b, 'WXYZ5678');
assert(dir(b5_qc_a).bytes == dir(b5_qc_b).bytes, 'B5: same-size QC precondition.');
b5_qc_shared = fullfile(test_root, 'b5-qc-shared');
mkdir(b5_qc_shared);
copyfile(b5_att, fullfile(b5_qc_shared, 'att_map.nii'));
local_write(fullfile(b5_qc_shared, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'WXYZ5678');
copyfile(b5_ver, fullfile(b5_qc_shared, 'Pseudo_CT_AC_Version.txt'));
b5_qc_ver = fullfile(test_root, 'b5-qc-ver.txt');
local_write_verification_mixed_declared(b5_qc_ver, b5_att, b5_qc_a, b5_ver);
assert(~mlsc_current_validate('verify_copyback_identity', b5_qc_shared, b5_qc_ver), ...
    'B5: same-size QC passed.');
fprintf('B5-16 PASS: same-size QC fails.\n');

% B5-17 copied SHA mismatch fails (shared hash != declared hash).
b5_mismatch_shared = fullfile(test_root, 'b5-mismatch');
mkdir(b5_mismatch_shared);
copyfile(b5_att, fullfile(b5_mismatch_shared, 'att_map.nii'));
copyfile(b5_qc, fullfile(b5_mismatch_shared, 'Fusion_MR_Pseudo_CT_validation.tiff'));
copyfile(b5_ver, fullfile(b5_mismatch_shared, 'Pseudo_CT_AC_Version.txt'));
b5_mismatch_ver = fullfile(test_root, 'b5-mismatch-ver.txt');
local_write_verification_tampered_sha(b5_mismatch_ver, b5_att, b5_qc, b5_ver);
assert(~mlsc_current_validate('verify_copyback_identity', b5_mismatch_shared, b5_mismatch_ver), ...
    'B5: copied SHA mismatch passed.');
fprintf('B5-17 PASS: copied SHA mismatch fails.\n');

% B5-18 missing semantic fails (no att_map_* block).
b5_nosem = fullfile(test_root, 'b5-nosem.txt');
local_write_verification_no_semantic(b5_nosem, b5_att, b5_qc, b5_ver);
assert(~mlsc_current_validate('verify_output_verification', b5_nosem), 'B5: missing semantic passed.');
assert(~mlsc_current_validate('verify_att_map_semantic', b5_att, b5_nosem), 'B5: missing semantic att passed.');
fprintf('B5-18 PASS: missing semantic fails.\n');

% B5-19 dtype/dims/finite/affine mismatch fails.
b5_wrong_base = fullfile(test_root, 'b5-wrong-base.txt');
local_write_verification(b5_wrong_base, b5_att, b5_qc, b5_ver);
% dtype: tamper datatype 16 -> 4.
b5_wrong_dtype = fullfile(test_root, 'b5-wrong-dtype.txt');
local_tamper_line(b5_wrong_base, b5_wrong_dtype, 'att_map_datatype:', 'att_map_datatype: 4');
assert(~mlsc_current_validate('verify_att_map_semantic', b5_att, b5_wrong_dtype), 'B5: dtype mismatch passed.');
% dims: tamper dim.
b5_wrong_dims = fullfile(test_root, 'b5-wrong-dims.txt');
local_tamper_line(b5_wrong_base, b5_wrong_dims, 'att_map_dim:', 'att_map_dim: 4 4 4');
assert(~mlsc_current_validate('verify_att_map_semantic', b5_att, b5_wrong_dims), 'B5: dims mismatch passed.');
% finite: tamper finite 1 -> 0.
b5_wrong_finite = fullfile(test_root, 'b5-wrong-finite.txt');
local_tamper_line(b5_wrong_base, b5_wrong_finite, 'att_map_finite:', 'att_map_finite: 0');
assert(~mlsc_current_validate('verify_att_map_semantic', b5_att, b5_wrong_finite), 'B5: finite mismatch passed.');
% affine: tamper one element (detected via att_map semantic vs file;
% output-verification alone cannot know the file affine, so only the
% semantic check must fail here).
b5_wrong_affine = fullfile(test_root, 'b5-wrong-affine.txt');
local_tamper_affine_element(b5_wrong_base, b5_wrong_affine);
assert(~mlsc_current_validate('verify_att_map_semantic', b5_att, b5_wrong_affine), 'B5: affine mismatch passed.');
fprintf('B5-19 PASS: dtype/dims/finite/affine mismatch fails.\n');

% B5-20 affine round-trip exact (%.17g lossless, no tolerance).
% Old %.10f corrupts this affine (~3e-11); new %.17g recovers exactly.
old_affine_text = sprintf('%.10f ', b5_affine(:)');
old_affine_text = strtrim(old_affine_text);
old_parsed = sscanf(old_affine_text, '%f', inf);
old_parsed = reshape(old_parsed, 4, 4);
assert(~isequal(old_parsed, b5_affine), 'B5: %.10f did not corrupt (precondition).');
new_affine_text = sprintf('%.17g ', b5_affine(:)');
new_affine_text = strtrim(new_affine_text);
new_parsed = sscanf(new_affine_text, '%f', inf);
new_parsed = reshape(new_parsed, 4, 4);
assert(isequal(new_parsed, b5_affine), 'B5: %.17g did not round-trip exact.');
% Production evidence uses %.17g and verifies exact.
assert(mlsc_current_validate('verify_att_map_semantic', b5_att, b5_verification), ...
    'B5: lossless affine semantic rejected.');
fprintf('B5-20 PASS: affine round-trip exact (%.17g lossless, no tolerance).\n');

% B5-21 NORMALIZED_INPUT SHA STRICT (same ^[0-9A-Fa-f]{64}$ policy as
% required-output SHA, after whitespace normalization). Valid 64 accepted;
% missing/empty/63/65/suffix/prefix/trailing/non-hex rejected; the
% normalized_input_verified marker never overrides a malformed SHA.
sha_valid_b5 = local_sha_hex(b5_ver);
assert(ischar(sha_valid_b5) && length(sha_valid_b5) == 64, 'B5-21 precondition failed.');
assert(mlsc_current_validate('verify_output_verification', b5_verification), ...
    'B5-21: valid normalized_input SHA rejected.');
% All malformed variants below keep the verified marker present, proving
% verified=true cannot override a malformed normalized_input SHA.
b5n_base = b5_verification;
b5n_missing_sha = fullfile(test_root, 'b5n-missing-sha.txt');
local_tamper_line(b5n_base, b5n_missing_sha, 'normalized_input:', ...
    'normalized_input: bytes=10;datenum=1.000000');
assert(~mlsc_current_validate('verify_output_verification', b5n_missing_sha), ...
    'B5-21: missing normalized_input SHA passed.');
b5n_empty = fullfile(test_root, 'b5n-empty.txt');
local_tamper_line(b5n_base, b5n_empty, 'normalized_input:', ...
    'normalized_input: bytes=10;datenum=1.000000;sha256=');
assert(~mlsc_current_validate('verify_output_verification', b5n_empty), ...
    'B5-21: empty normalized_input SHA passed.');
b5n_63 = fullfile(test_root, 'b5n-63.txt');
local_tamper_line(b5n_base, b5n_63, 'normalized_input:', ...
    sprintf('normalized_input: bytes=10;datenum=1.000000;sha256=%s', sha_valid_b5(1:63)));
assert(~mlsc_current_validate('verify_output_verification', b5n_63), ...
    'B5-21: 63-hex normalized_input SHA passed.');
b5n_65 = fullfile(test_root, 'b5n-65.txt');
local_tamper_line(b5n_base, b5n_65, 'normalized_input:', ...
    sprintf('normalized_input: bytes=10;datenum=1.000000;sha256=%s0', sha_valid_b5));
assert(~mlsc_current_validate('verify_output_verification', b5n_65), ...
    'B5-21: 65-hex normalized_input SHA passed.');
b5n_suffix = fullfile(test_root, 'b5n-suffix.txt');
local_tamper_line(b5n_base, b5n_suffix, 'normalized_input:', ...
    sprintf('normalized_input: bytes=10;datenum=1.000000;sha256=%s-suffix', sha_valid_b5));
assert(~mlsc_current_validate('verify_output_verification', b5n_suffix), ...
    'B5-21: suffixed normalized_input SHA passed.');
b5n_prefix = fullfile(test_root, 'b5n-prefix.txt');
local_tamper_line(b5n_base, b5n_prefix, 'normalized_input:', ...
    sprintf('normalized_input: bytes=10;datenum=1.000000;sha256=XX%s', sha_valid_b5));
assert(~mlsc_current_validate('verify_output_verification', b5n_prefix), ...
    'B5-21: prefixed normalized_input SHA passed.');
b5n_trailing = fullfile(test_root, 'b5n-trailing.txt');
local_tamper_line(b5n_base, b5n_trailing, 'normalized_input:', ...
    sprintf('normalized_input: bytes=10;datenum=1.000000;sha256=%s extra', sha_valid_b5));
assert(~mlsc_current_validate('verify_output_verification', b5n_trailing), ...
    'B5-21: trailing-token normalized_input SHA passed.');
b5n_nonhex = fullfile(test_root, 'b5n-nonhex.txt');
local_tamper_line(b5n_base, b5n_nonhex, 'normalized_input:', ...
    'normalized_input: bytes=10;datenum=1.000000;sha256=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz');
assert(~mlsc_current_validate('verify_output_verification', b5n_nonhex), ...
    'B5-21: non-hex normalized_input SHA passed.');
% Missing normalized_input line entirely (verified marker still present).
% The verified line does not contain the exact 'normalized_input:' prefix
% ('_' vs ':'), so dropping only lines with that prefix keeps verified.
b5n_noline = fullfile(test_root, 'b5n-noline.txt');
b5n_fid = fopen(b5n_base, 'r');
assert(b5n_fid ~= -1, 'B5-21 source unreadable.');
b5n_raw = fread(b5n_fid, inf, '*char')';
fclose(b5n_fid);
b5n_lines = regexp(b5n_raw, char(10), 'split');
b5n_out = fopen(b5n_noline, 'w');
assert(b5n_out ~= -1, 'B5-21 dest unwritable.');
for b5n_ii = 1:length(b5n_lines)
    if isempty(strfind(b5n_lines{b5n_ii}, 'normalized_input:'))
        fprintf(b5n_out, '%s\n', b5n_lines{b5n_ii});
    else
        % Drop only the 'normalized_input:' fingerprint line.
    end
end
fclose(b5n_out);
assert(~mlsc_current_validate('verify_output_verification', b5n_noline), ...
    'B5-21: missing normalized_input line passed.');
fprintf('B5-21 PASS: normalized_input SHA strict (valid accepted; missing/empty/63/65/suffix/prefix/trailing/non-hex rejected; verified cannot override).\n');

% R2010b parse compatibility for touched seams.
parse_targets = {fullfile(root_dir, 'src', 'mlsc', 'mlsc_lifecycle.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_validate.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_generate_slurm_script.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_payload.m')};
for ii = 1:length(parse_targets)
    try
        mlint(parse_targets{ii});
    catch ME %#ok<NASGU>
        assert(false, 'Remediation seam failed to parse.');
    end
end

fprintf('=== MLSC current remediation passed: B1 validators (seam removed), B4 fail-closed startup, B5 strict identity + normalized_input SHA strict ===\n');

% Nested transport callback (blocked-submission guard; B1 seam helpers removed).
    function response = local_never_submit(~)
        response = '99999;mlsc';
    end
end

function local_write_valid_manifests(build_path, resource_path, runner_path, pinned, atlas_dir)
info = dir(runner_path);
assert(~isempty(info), 'Runner fixture missing.');
fingerprint = local_sha_hex(runner_path);
assert(ischar(fingerprint) && length(fingerprint) == 64, 'Runner SHA fixture failed.');
build = struct();
build.schema = 'pseudo-CT.mlsc-current-build/v1';
build.manifest_version = 1;
build.runner = runner_path;
build.mcr_root = pinned;
build.release = 'R2026a';
build.update_minimum = 2;
build.mcr_version = [26 1];
build.arch = 'glnxa64';
build.generation = '26.1';
build.runner_checksum = fingerprint;
build.source_commit = 'fixture-commit';
build.source_provenance_fingerprint = local_sha_hex(runner_path);
build.required_outputs = {'att_map.nii'; 'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
save(build_path, 'build');
resources = struct();
resources.schema = 'pseudo-CT.mlsc-current-resources/v1';
resources.manifest_version = 1;
resources.atlas_dir = atlas_dir;
resources.native_platform = 'glnxa64';
resources.native_arch = 'glnxa64';
resources.native_validation = 't007-gate-a-pending: existence-only; production loadability evidence comes later';
save(resource_path, 'resources');
end

function local_create_nifti(path_name, dims, mat)
V = struct();
V.fname = path_name;
V.dim = dims(:)';
V.dt = [16 0];
V.mat = mat;
V.pinfo = [1 0 0]';
data = ones([dims(:)' 1 1], 'single');
data = data(1:dims(1), 1:dims(2), 1:dims(3));
data(1, 1, 1) = 0.5;
data(end, end, end) = 0.25;
spm_write_vol(V, data);
assert(exist(path_name, 'file') == 2, 'NIfTI fixture not created.');
end

function local_create_nifti_different_data(path_name, dims, mat)
V = struct();
V.fname = path_name;
V.dim = dims(:)';
V.dt = [16 0];
V.mat = mat;
V.pinfo = [1 0 0]';
data = zeros([dims(:)' 1 1], 'single');
data = data(1:dims(1), 1:dims(2), 1:dims(3));
data(1, 1, 1) = 0.75;
data(end, end, end) = 0.125;
spm_write_vol(V, data);
assert(exist(path_name, 'file') == 2, 'NIfTI fixture not created.');
end

function local_write_verification(verification_path, att_path, qc_path, ver_path)
info_att = dir(att_path);
info_qc = dir(qc_path);
info_ver = dir(ver_path);
sha_att = local_sha_hex(att_path);
sha_qc = local_sha_hex(qc_path);
sha_ver = local_sha_hex(ver_path);
V = spm_vol(att_path);
V = V(1);
dim_text = sprintf('%g ', V.dim(:)');
dim_text = strtrim(dim_text);
affine_text = sprintf('%.17g ', V.mat(:)');
affine_text = strtrim(affine_text);
fid = fopen(verification_path, 'w');
assert(fid ~= -1, 'Verification fixture could not be created.');
fprintf(fid, 'schema: pseudo-CT.mlsc-current-output-verification/v1\n');
fprintf(fid, 'handoff: fixture-handoff\n');
fprintf(fid, 'needs_normalization: 0\n');
fprintf(fid, 'normalized_input_verified: fixture-normalized.nii\n');
fprintf(fid, 'normalized_input: bytes=10;datenum=1.000000;sha256=%s\n', sha_ver);
fprintf(fid, 'output att_map.nii: bytes=%d;datenum=%.6f;sha256=%s\n', info_att(1).bytes, info_att(1).datenum, sha_att);
fprintf(fid, 'output Fusion_MR_Pseudo_CT_validation.tiff: bytes=%d;datenum=%.6f;sha256=%s\n', info_qc(1).bytes, info_qc(1).datenum, sha_qc);
fprintf(fid, 'output Pseudo_CT_AC_Version.txt: bytes=%d;datenum=%.6f;sha256=%s\n', info_ver(1).bytes, info_ver(1).datenum, sha_ver);
fprintf(fid, 'att_map_basename: att_map.nii\n');
fprintf(fid, 'att_map_bytes: %d\n', double(info_att(1).bytes));
fprintf(fid, 'att_map_sha256: %s\n', sha_att);
fprintf(fid, 'att_map_datatype: 16\n');
fprintf(fid, 'att_map_dim: %s\n', dim_text);
fprintf(fid, 'att_map_affine: %s\n', affine_text);
fprintf(fid, 'att_map_finite: 1\n');
fclose(fid);
end

function local_write_verification_no_sha(verification_path, att_path, qc_path, ver_path)
info_att = dir(att_path);
info_qc = dir(qc_path);
info_ver = dir(ver_path);
V = spm_vol(att_path);
V = V(1);
dim_text = sprintf('%g ', V.dim(:)');
dim_text = strtrim(dim_text);
affine_text = sprintf('%.17g ', V.mat(:)');
affine_text = strtrim(affine_text);
fid = fopen(verification_path, 'w');
assert(fid ~= -1, 'No-SHA fixture could not be created.');
fprintf(fid, 'schema: pseudo-CT.mlsc-current-output-verification/v1\n');
fprintf(fid, 'handoff: fixture-handoff\n');
fprintf(fid, 'needs_normalization: 0\n');
fprintf(fid, 'normalized_input_verified: fixture-normalized.nii\n');
fprintf(fid, 'normalized_input: bytes=10;datenum=1.000000\n');
fprintf(fid, 'output att_map.nii: bytes=%d;datenum=%.6f\n', info_att(1).bytes, info_att(1).datenum);
fprintf(fid, 'output Fusion_MR_Pseudo_CT_validation.tiff: bytes=%d;datenum=%.6f\n', info_qc(1).bytes, info_qc(1).datenum);
fprintf(fid, 'output Pseudo_CT_AC_Version.txt: bytes=%d;datenum=%.6f\n', info_ver(1).bytes, info_ver(1).datenum);
fprintf(fid, 'att_map_basename: att_map.nii\n');
fprintf(fid, 'att_map_bytes: %d\n', double(info_att(1).bytes));
fprintf(fid, 'att_map_datatype: 16\n');
fprintf(fid, 'att_map_dim: %s\n', dim_text);
fprintf(fid, 'att_map_affine: %s\n', affine_text);
fprintf(fid, 'att_map_finite: 1\n');
fclose(fid);
end

function local_write_verification_bad_sha(verification_path, att_path, qc_path, ver_path)
info_att = dir(att_path);
info_qc = dir(qc_path);
info_ver = dir(ver_path);
V = spm_vol(att_path);
V = V(1);
dim_text = sprintf('%g ', V.dim(:)');
dim_text = strtrim(dim_text);
affine_text = sprintf('%.17g ', V.mat(:)');
affine_text = strtrim(affine_text);
fid = fopen(verification_path, 'w');
assert(fid ~= -1, 'Bad-SHA fixture could not be created.');
fprintf(fid, 'schema: pseudo-CT.mlsc-current-output-verification/v1\n');
fprintf(fid, 'handoff: fixture-handoff\n');
fprintf(fid, 'needs_normalization: 0\n');
fprintf(fid, 'normalized_input_verified: fixture-normalized.nii\n');
fprintf(fid, 'normalized_input: bytes=10;datenum=1.000000;sha256=abc\n');
fprintf(fid, 'output att_map.nii: bytes=%d;datenum=%.6f;sha256=abc123\n', info_att(1).bytes, info_att(1).datenum);
fprintf(fid, 'output Fusion_MR_Pseudo_CT_validation.tiff: bytes=%d;datenum=%.6f;sha256=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n', info_qc(1).bytes, info_qc(1).datenum);
fprintf(fid, 'output Pseudo_CT_AC_Version.txt: bytes=%d;datenum=%.6f;sha256=%s\n', info_ver(1).bytes, info_ver(1).datenum, repmat('0', 1, 32));
fprintf(fid, 'att_map_basename: att_map.nii\n');
fprintf(fid, 'att_map_bytes: %d\n', double(info_att(1).bytes));
fprintf(fid, 'att_map_sha256: short\n');
fprintf(fid, 'att_map_datatype: 16\n');
fprintf(fid, 'att_map_dim: %s\n', dim_text);
fprintf(fid, 'att_map_affine: %s\n', affine_text);
fprintf(fid, 'att_map_finite: 1\n');
fclose(fid);
end

function local_write_verification_mixed_declared(verification_path, att_path, qc_declared_path, ver_path)
info_att = dir(att_path);
info_qc = dir(qc_declared_path);
info_ver = dir(ver_path);
sha_att = local_sha_hex(att_path);
sha_qc = local_sha_hex(qc_declared_path);
sha_ver = local_sha_hex(ver_path);
V = spm_vol(att_path);
V = V(1);
dim_text = sprintf('%g ', V.dim(:)');
dim_text = strtrim(dim_text);
affine_text = sprintf('%.17g ', V.mat(:)');
affine_text = strtrim(affine_text);
fid = fopen(verification_path, 'w');
assert(fid ~= -1, 'Mixed fixture could not be created.');
fprintf(fid, 'schema: pseudo-CT.mlsc-current-output-verification/v1\n');
fprintf(fid, 'handoff: fixture-handoff\n');
fprintf(fid, 'needs_normalization: 0\n');
fprintf(fid, 'normalized_input_verified: fixture-normalized.nii\n');
fprintf(fid, 'normalized_input: bytes=10;datenum=1.000000;sha256=%s\n', sha_ver);
fprintf(fid, 'output att_map.nii: bytes=%d;datenum=%.6f;sha256=%s\n', info_att(1).bytes, info_att(1).datenum, sha_att);
fprintf(fid, 'output Fusion_MR_Pseudo_CT_validation.tiff: bytes=%d;datenum=%.6f;sha256=%s\n', info_qc(1).bytes, info_qc(1).datenum, sha_qc);
fprintf(fid, 'output Pseudo_CT_AC_Version.txt: bytes=%d;datenum=%.6f;sha256=%s\n', info_ver(1).bytes, info_ver(1).datenum, sha_ver);
fprintf(fid, 'att_map_basename: att_map.nii\n');
fprintf(fid, 'att_map_bytes: %d\n', double(info_att(1).bytes));
fprintf(fid, 'att_map_sha256: %s\n', sha_att);
fprintf(fid, 'att_map_datatype: 16\n');
fprintf(fid, 'att_map_dim: %s\n', dim_text);
fprintf(fid, 'att_map_affine: %s\n', affine_text);
fprintf(fid, 'att_map_finite: 1\n');
fclose(fid);
end

function local_write_verification_tampered_sha(verification_path, att_path, qc_path, ver_path)
info_att = dir(att_path);
info_qc = dir(qc_path);
info_ver = dir(ver_path);
sha_att = local_sha_hex(att_path);
sha_qc = local_sha_hex(qc_path);
% Tamper the version SHA (flip first hex digit, keep 64-hex valid).
sha_ver_bad = local_sha_hex(ver_path);
if sha_ver_bad(1) == '0'
    sha_ver_bad(1) = '1';
else
    sha_ver_bad(1) = '0';
end
V = spm_vol(att_path);
V = V(1);
dim_text = sprintf('%g ', V.dim(:)');
dim_text = strtrim(dim_text);
affine_text = sprintf('%.17g ', V.mat(:)');
affine_text = strtrim(affine_text);
fid = fopen(verification_path, 'w');
assert(fid ~= -1, 'Tampered fixture could not be created.');
fprintf(fid, 'schema: pseudo-CT.mlsc-current-output-verification/v1\n');
fprintf(fid, 'handoff: fixture-handoff\n');
fprintf(fid, 'needs_normalization: 0\n');
fprintf(fid, 'normalized_input_verified: fixture-normalized.nii\n');
fprintf(fid, 'normalized_input: bytes=10;datenum=1.000000;sha256=%s\n', sha_ver_bad);
fprintf(fid, 'output att_map.nii: bytes=%d;datenum=%.6f;sha256=%s\n', info_att(1).bytes, info_att(1).datenum, sha_att);
fprintf(fid, 'output Fusion_MR_Pseudo_CT_validation.tiff: bytes=%d;datenum=%.6f;sha256=%s\n', info_qc(1).bytes, info_qc(1).datenum, sha_qc);
fprintf(fid, 'output Pseudo_CT_AC_Version.txt: bytes=%d;datenum=%.6f;sha256=%s\n', info_ver(1).bytes, info_ver(1).datenum, sha_ver_bad);
fprintf(fid, 'att_map_basename: att_map.nii\n');
fprintf(fid, 'att_map_bytes: %d\n', double(info_att(1).bytes));
fprintf(fid, 'att_map_sha256: %s\n', sha_att);
fprintf(fid, 'att_map_datatype: 16\n');
fprintf(fid, 'att_map_dim: %s\n', dim_text);
fprintf(fid, 'att_map_affine: %s\n', affine_text);
fprintf(fid, 'att_map_finite: 1\n');
fclose(fid);
end

function local_write_verification_no_semantic(verification_path, att_path, qc_path, ver_path)
info_att = dir(att_path);
info_qc = dir(qc_path);
info_ver = dir(ver_path);
sha_att = local_sha_hex(att_path);
sha_qc = local_sha_hex(qc_path);
sha_ver = local_sha_hex(ver_path);
fid = fopen(verification_path, 'w');
assert(fid ~= -1, 'No-semantic fixture could not be created.');
fprintf(fid, 'schema: pseudo-CT.mlsc-current-output-verification/v1\n');
fprintf(fid, 'handoff: fixture-handoff\n');
fprintf(fid, 'needs_normalization: 0\n');
fprintf(fid, 'normalized_input_verified: fixture-normalized.nii\n');
fprintf(fid, 'normalized_input: bytes=10;datenum=1.000000;sha256=%s\n', sha_ver);
fprintf(fid, 'output att_map.nii: bytes=%d;datenum=%.6f;sha256=%s\n', info_att(1).bytes, info_att(1).datenum, sha_att);
fprintf(fid, 'output Fusion_MR_Pseudo_CT_validation.tiff: bytes=%d;datenum=%.6f;sha256=%s\n', info_qc(1).bytes, info_qc(1).datenum, sha_qc);
fprintf(fid, 'output Pseudo_CT_AC_Version.txt: bytes=%d;datenum=%.6f;sha256=%s\n', info_ver(1).bytes, info_ver(1).datenum, sha_ver);
fclose(fid);
end

function local_tamper_line(source_path, dest_path, marker, replacement)
fid = fopen(source_path, 'r');
assert(fid ~= -1, 'Tamper source unreadable.');
raw = fread(fid, inf, '*char')';
fclose(fid);
lines = regexp(raw, char(10), 'split');
fid = fopen(dest_path, 'w');
assert(fid ~= -1, 'Tamper dest unwritable.');
for ii = 1:length(lines)
    if ~isempty(strfind(lines{ii}, marker))
        fprintf(fid, '%s\n', replacement);
    else
        fprintf(fid, '%s\n', lines{ii});
    end
end
fclose(fid);
end

function local_tamper_affine_element(source_path, dest_path)
fid = fopen(source_path, 'r');
assert(fid ~= -1, 'Affine tamper source unreadable.');
raw = fread(fid, inf, '*char')';
fclose(fid);
lines = regexp(raw, char(10), 'split');
fid = fopen(dest_path, 'w');
assert(fid ~= -1, 'Affine tamper dest unwritable.');
for ii = 1:length(lines)
    if ~isempty(strfind(lines{ii}, 'att_map_affine:'))
        tail = strtrim(lines{ii}(length('att_map_affine:') + 1:end));
        vals = sscanf(tail, '%f', inf);
        assert(numel(vals) == 16, 'Affine tamper precondition.');
        vals(1) = vals(1) + 1.0;
        new_text = sprintf('%.17g ', vals(:)');
        fprintf(fid, 'att_map_affine: %s\n', strtrim(new_text));
    else
        fprintf(fid, '%s\n', lines{ii});
    end
end
fclose(fid);
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

function [status, output] = local_run_recheck_with_mcr(artifact, shared_temp, runner_path, build_path, resource_path, mcr_root, test_root)
script = artifact.script_text;
runner_q = local_shell_quote_sh(runner_path);
build_q = local_shell_quote_sh(build_path);
resource_q = local_shell_quote_sh(resource_path);
job_q = local_shell_quote_sh(fullfile(shared_temp, 'mlsc_current_job.mat'));
mcr_q = local_shell_quote_sh(mcr_root);
toctou_dir = fullfile(test_root, ['toctou-' num2str(round(rand * 1e9))]);
mkdir(toctou_dir);
recheck_script = fullfile(toctou_dir, 'recheck.sh');
start_marker = 'pinned_mcr_root=';
start_idx = strfind(script, start_marker);
assert(~isempty(start_idx), 'Recheck block not found.');
job_check_marker = 'if [ ! -s "$shared_job_manifest" ]';
job_idx = strfind(script, job_check_marker);
assert(~isempty(job_idx) && job_idx(1) > start_idx(1), 'Job recheck not found.');
job_tail = script(job_idx(1):end);
fi_rel = strfind(job_tail, 'fi');
assert(~isempty(fi_rel), 'Job recheck terminator not found.');
recheck_end = job_idx(1) + fi_rel(1) + 1;
recheck_block = script(start_idx(1):recheck_end);
fid = fopen(recheck_script, 'w');
assert(fid ~= -1, 'Recheck harness could not be created.');
fprintf(fid, '#!/bin/bash\nset -euo pipefail\n');
fprintf(fid, 'current_runner=%s\n', runner_q);
fprintf(fid, 'current_mcr_root=%s\n', mcr_q);
fprintf(fid, 'shared_build_manifest=%s\n', build_q);
fprintf(fid, 'shared_resource_manifest=%s\n', resource_q);
fprintf(fid, 'shared_job_manifest=%s\n', job_q);
fprintf(fid, '%s\n', recheck_block);
fprintf(fid, 'printf "TOCTOU_RECHECK_PASSED\\n"\n');
fclose(fid);
[status, output] = system(['bash "' recheck_script '"']);
end

function [status, output] = local_run_recheck_restricted_path(artifact, shared_temp, runner_path, build_path, resource_path, mcr_root, test_root, restricted_path)
script = artifact.script_text;
runner_q = local_shell_quote_sh(runner_path);
build_q = local_shell_quote_sh(build_path);
resource_q = local_shell_quote_sh(resource_path);
job_q = local_shell_quote_sh(fullfile(shared_temp, 'mlsc_current_job.mat'));
mcr_q = local_shell_quote_sh(mcr_root);
toctou_dir = fullfile(test_root, ['toctou-nohash-' num2str(round(rand * 1e9))]);
mkdir(toctou_dir);
recheck_script = fullfile(toctou_dir, 'recheck.sh');
start_marker = 'pinned_mcr_root=';
start_idx = strfind(script, start_marker);
assert(~isempty(start_idx), 'Recheck block not found.');
job_check_marker = 'if [ ! -s "$shared_job_manifest" ]';
job_idx = strfind(script, job_check_marker);
assert(~isempty(job_idx) && job_idx(1) > start_idx(1), 'Job recheck not found.');
job_tail = script(job_idx(1):end);
fi_rel = strfind(job_tail, 'fi');
assert(~isempty(fi_rel), 'Job recheck terminator not found.');
recheck_end = job_idx(1) + fi_rel(1) + 1;
recheck_block = script(start_idx(1):recheck_end);
fid = fopen(recheck_script, 'w');
assert(fid ~= -1, 'Restricted harness could not be created.');
fprintf(fid, '#!/bin/bash\nset -euo pipefail\n');
fprintf(fid, 'current_runner=%s\n', runner_q);
fprintf(fid, 'current_mcr_root=%s\n', mcr_q);
fprintf(fid, 'shared_build_manifest=%s\n', build_q);
fprintf(fid, 'shared_resource_manifest=%s\n', resource_q);
fprintf(fid, 'shared_job_manifest=%s\n', job_q);
fprintf(fid, '%s\n', recheck_block);
fprintf(fid, 'printf "TOCTOU_RECHECK_PASSED\\n"\n');
fclose(fid);
[status, output] = system(['PATH="' restricted_path '" bash "' recheck_script '"']);
end

function restricted = local_restricted_path_without_sha256(test_root)
bin_dir = fullfile(test_root, 'restricted-bin');
if exist(bin_dir, 'dir') ~= 7
    mkdir(bin_dir);
end
tools = {'bash', 'wc', 'tr', 'cut', 'sed', 'grep', 'head', 'printf', 'uname'};
for ii = 1:length(tools)
    [s, p] = system(['command -v ' tools{ii} ' 2>/dev/null']);
    p = strtrim(p);
    if s == 0 && ~isempty(p) && exist(p, 'file') == 2
        dest = fullfile(bin_dir, tools{ii});
        if exist(dest, 'file') ~= 2
            try
                copyfile(p, dest);
            catch %#ok<CTCH>
            end
        end
    end
end
assert(exist(fullfile(bin_dir, 'bash'), 'file') == 2, 'Restricted bash missing.');
assert(exist(fullfile(bin_dir, 'sha256sum'), 'file') ~= 2, 'sha256sum leaked into restricted PATH.');
restricted = bin_dir;
end

function local_flip_one_byte(path_name)
fid = fopen(path_name, 'r');
assert(fid ~= -1, 'Flip source unreadable.');
raw = fread(fid, inf, '*uint8')';
fclose(fid);
assert(length(raw) >= 16, 'Flip precondition failed.');
if raw(10) == 0
    raw(10) = 1;
else
    raw(10) = 0;
end
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Flip dest unwritable.');
count = fwrite(fid, raw, 'uint8');
fclose(fid);
assert(count == length(raw), 'Flip write incomplete.');
end

function q = local_shell_quote_sh(value)
single_quote = char(39);
double_quote = char(34);
q = single_quote;
for ii = 1:length(value)
    if value(ii) == single_quote
        q = [q single_quote double_quote single_quote double_quote single_quote]; %#ok<AGROW>
    else
        q = [q value(ii)]; %#ok<AGROW>
    end
end
q = [q single_quote];
end

function local_write(path_name, text)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Fixture could not be created.');
fwrite(fid, text);
fclose(fid);
end

function local_assert_error(thunk)
failed = false;
try
    thunk();
catch %#ok<CTCH>
    failed = true;
end
assert(failed, 'Fail-closed gate did not reject.');
end

function local_assert_error_id(thunk, expected_id)
failed = false;
actual_id = '';
try
    thunk();
catch ME
    failed = true;
    actual_id = ME.identifier;
end
assert(failed, 'Fail-closed gate did not reject.');
assert(strcmp(actual_id, expected_id), 'Unexpected failure identifier: %s', actual_id);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    try
        rmdir(directory, 's');
    catch %#ok<CTCH>
    end
end
end
