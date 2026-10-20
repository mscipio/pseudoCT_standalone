function test_mlsc_current_gate_a_record()
%TEST_MLSC_CURRENT_GATE_A_RECORD T015 offline manifest/record verification.
%   Offline only (no live SSH/sbatch, no Gates/production, no rebuild,
%   no catalog/resolver, no /usr/pubsw mutation). Covers:
%     A) canonical build-manifest schema consumed by the validator
%        (11 required fields, pinned root, canonical outputs,
%        provenance fingerprint, malformed failures, old-builder schema
%        rejection);
%     B) 15 structured Gate-A record cases (fixture-PASS, missing,
%        malformed, pending/no-file, wrong runner/exe/build/resource/
%        provenance/MCR/release/update/arch, missing-or-failed natives,
%        foreign record);
%     C) arbitrary-string/old-marker/basename-size/legacy/resolver
%        rejection plus finalizer no-self-certify refusal.
%   Fixture records minted here are test-only (they bind fixture paths)
%   and unusable as production evidence. No real PASS record is claimed.
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
addpath(genpath(fullfile(root_dir, 'src')), '-begin');

pinned = mlsc_current_validate('pinned_mcr_root');
assert(strcmp(pinned, '/usr/pubsw/common/matlab/26.1'), 'Pinned MCR_ROOT drifted.');
assert(exist(pinned, 'dir') == 7, 'Pinned MCR_ROOT unavailable.');
assert(exist(fullfile(pinned, 'runtime', 'glnxa64'), 'dir') == 7, ...
    'Pinned MCR_ROOT structure malformed.');
actual_pinned = mlsc_current_validate('actual_identity', pinned);
assert(strcmp(actual_pinned.release, 'R2026a'), 'Pinned release mismatch.');
assert(actual_pinned.update == 2, 'Pinned update is not 2.');
assert(isequal(actual_pinned.mcr_version, [26 1]), 'Pinned mcrversion mismatch.');
assert(strcmp(actual_pinned.arch, 'glnxa64'), 'Pinned arch mismatch.');
assert(strcmp(actual_pinned.generation, '26.1'), 'Pinned generation mismatch.');
assert(strcmp(mlsc_current_validate('gate_a_schema'), ...
    'pseudo-CT.mlsc-current-gate-a/v1'), 'Gate-A schema drifted.');

test_root = tempname;
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

freesurfer_env = fullfile(test_root, 'freesurfer-env');
local_write(freesurfer_env, '# fixture');
shell_path = '/bin/bash';
atlas_dir = fullfile(test_root, 'Batch_atlas_current');
mkdir(atlas_dir);
prov_text = fullfile(test_root, 'provenance-seed.txt');
local_write(prov_text, 'fixture-provenance-seed');
prov_fp = local_sha_hex(prov_text);

% Base candidate fixtures (canonical schema, pending resources).
base_runner = fullfile(test_root, 'run_mlsc_current_payload.sh');
local_write(base_runner, '# fixture runner T015');
base_exe = fullfile(test_root, 'mlsc_current_payload');
local_write(base_exe, '# fixture exe T015');
base_build = fullfile(test_root, 'build.mat');
base_resources = fullfile(test_root, 'resources.mat');
local_write_build(base_build, base_runner, pinned, 'fixture-commit', prov_fp);
local_write_resources(base_resources, atlas_dir, ...
    't007-gate-a-pending: existence-only; production loadability evidence comes later', {});
base_config = local_make_config(test_root, base_runner, pinned, ...
    base_build, base_resources, shell_path, freesurfer_env, '');

% ------------------------------------------------------------------
% A) Canonical manifest schema.
% ------------------------------------------------------------------
% A1: valid canonical build + pending resources: contract passes,
% execution stays blocked with no record (pending/no-record fail-closed).
mlsc_current_validate('validate_contract', base_config);
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    base_config), 'pseudo_CT:MLSCCurrentNativeEvidence');
fprintf('A1 PASS: canonical schema passes contract; execution blocked without record.\n');

% A2: each of the 11 required fields missing fails closed.
required_fields = {'runner'; 'mcr_root'; 'release'; 'update_minimum'; ...
    'mcr_version'; 'arch'; 'generation'; 'runner_checksum'; ...
    'source_commit'; 'source_provenance_fingerprint'; ...
    'required_outputs'};
for ii = 1:length(required_fields)
    tampered = load(base_build);
    build = rmfield(tampered.build, required_fields{ii});
    missing_path = fullfile(test_root, sprintf('build-missing-%d.mat', ii));
    save(missing_path, 'build');
    bad_config = base_config;
    bad_config.current.build_manifest = missing_path;
    local_assert_error_id(@() mlsc_current_validate('validate_contract', ...
        bad_config), 'pseudo_CT:MLSCCurrentManifest');
end
fprintf('A2 PASS: all 11 missing manifest fields fail closed.\n');

% A3: malformed values fail closed (one representative per field).
local_assert_manifest_fail(base_config, base_build, test_root, ...
    'runner', 'run_mlsc_current_payload.sh');
local_assert_manifest_fail(base_config, base_build, test_root, ...
    'mcr_root', '/usr/pubsw/common/matlab/current');
local_assert_manifest_fail(base_config, base_build, test_root, ...
    'release', 'R2026b');
local_assert_manifest_fail_struct(base_config, base_build, test_root, ...
    'update_minimum', 99);
local_assert_manifest_fail_struct(base_config, base_build, test_root, ...
    'mcr_version', [99 9]);
local_assert_manifest_fail(base_config, base_build, test_root, ...
    'arch', 'maci64');
local_assert_manifest_fail(base_config, base_build, test_root, ...
    'generation', '99.9');
local_assert_manifest_fail(base_config, base_build, test_root, ...
    'runner_checksum', 'bytes=123');
local_assert_manifest_fail(base_config, base_build, test_root, ...
    'source_commit', '');
local_assert_manifest_fail(base_config, base_build, test_root, ...
    'source_provenance_fingerprint', 'not-a-sha');
tampered = load(base_build);
build = tampered.build;
build.required_outputs = {'att_map.nii'; 'Pseudo_CT_AC_Version.txt'};
bad_outputs = fullfile(test_root, 'build-bad-outputs.mat');
save(bad_outputs, 'build');
bad_config = base_config;
bad_config.current.build_manifest = bad_outputs;
local_assert_error_id(@() mlsc_current_validate('validate_contract', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('A3 PASS: malformed manifest values fail closed (no basename/size fallback).\n');

% A4: old builder-style schema (dual synonymous sets, no canonical
% fields) cannot validate: the frozen T007 candidate is superseded for
% future gates, not silently accepted.
old_build = struct();
old_build.schema = 'pseudo-CT.mlsc-current-build/v1';
old_build.manifest_version = 1;
old_build.source_commit = 'fixture-commit';
old_build.expected_mcr_root = pinned;
old_build.required_runtime_release = '2026a';
old_build.required_runtime_mcr = [26 1];
old_build.required_runtime_min_update = 2;
old_build.required_runtime_arch = 'glnxa64';
old_build.runner = 'run_mlsc_current_payload.sh';
old_build.runner_fingerprint = local_sha_hex(base_runner);
build = old_build;
old_path = fullfile(test_root, 'build-old-schema.mat');
save(old_path, 'build');
bad_config = base_config;
bad_config.current.build_manifest = old_path;
local_assert_error_id(@() mlsc_current_validate('validate_contract', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('A4 PASS: old builder schema rejected (superseded, no dual sets).\n');

% ------------------------------------------------------------------
% B) 15 structured Gate-A record cases.
% ------------------------------------------------------------------
% Fixture natives declared in resources (coverage enforced).
native_names = {'native_a.mexa64'; 'native_b.mexa64'};
native_a = fullfile(test_root, 'native_a.mexa64');
native_b = fullfile(test_root, 'native_b.mexa64');
local_write(native_a, 'fixture-native-a-001');
local_write(native_b, 'fixture-native-b-002');
cand_resources = fullfile(test_root, 'cand-resources.mat');
local_write_resources(cand_resources, atlas_dir, ...
    't007-gate-a-pending: existence-only; production loadability evidence comes later', ...
    native_names);
cand_config = local_make_config(test_root, base_runner, pinned, ...
    base_build, cand_resources, shell_path, freesurfer_env, '');
candidate = struct('runner', base_runner, 'build_exe', base_exe, ...
    'build_manifest', base_build, 'resource_manifest', cand_resources, ...
    'mcr_root', pinned);
evidence = struct('native_names', {native_names}, ...
    'native_paths', {{native_a; native_b}}, ...
    'native_results', {{'pass'; 'pass'}}, ...
    'launcher_result', 'pass', 'runtime_lib_result', 'pass', ...
    'prepare_result', 'pass', 'compute_result', 'pass');
record_path = fullfile(test_root, 'mlsc_current_gate_a.mat');
mlsc_finalize_gate_a(candidate, evidence, record_path);
pass_config = cand_config;
pass_config.current.gate_a_record = record_path;

% B0 fixture-PASS: valid fixture record passes execution (test-only;
% binds fixture paths, unusable as production evidence).
mlsc_current_validate('validate_contract', pass_config);
mlsc_current_validate('validate_for_execution', pass_config);
fprintf('B0 PASS: fixture record passes execution (test-only, not production evidence).\n');

% B1 missing record field: execution blocked, contract passes.
mlsc_current_validate('validate_contract', cand_config);
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    cand_config), 'pseudo_CT:MLSCCurrentNativeEvidence');
fprintf('B1 PASS: missing record stays blocked.\n');

% B2 malformed record: wrong variable, wrong schema, bad version.
wrong_var = fullfile(test_root, 'record-wrongvar.mat');
not_gate_a = struct('schema', 'x');
save(wrong_var, 'not_gate_a');
bad_config = cand_config;
bad_config.current.gate_a_record = wrong_var;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
tampered_rec = load(record_path);
gate_a = tampered_rec.gate_a;
gate_a.schema = 'pseudo-CT.mlsc-current-gate-a/v0';
bad_schema = fullfile(test_root, 'record-badschema.mat');
save(bad_schema, 'gate_a');
bad_config.current.gate_a_record = bad_schema;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
gate_a = tampered_rec.gate_a;
gate_a.manifest_version = 2;
bad_version = fullfile(test_root, 'record-badversion.mat');
save(bad_version, 'gate_a');
bad_config.current.gate_a_record = bad_version;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B2 PASS: malformed records rejected (variable/schema/version).\n');

% B3 pending with record path absent on disk: blocked.
bad_config = cand_config;
bad_config.current.gate_a_record = fullfile(test_root, 'no-such-record.mat');
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentNativeEvidence');
fprintf('B3 PASS: pending (no record file) stays blocked.\n');

% B4 wrong runner: config runner swapped after finalization.
other_runner = fullfile(test_root, 'other-runner.sh');
local_write(other_runner, '# other runner');
bad_config = pass_config;
bad_config.current.runner = other_runner;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B4 PASS: wrong runner rejected.\n');

% B5 wrong exe: executable mutated after finalization.
fid = fopen(base_exe, 'a');
fwrite(fid, 'mutated');
fclose(fid);
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    pass_config), 'pseudo_CT:MLSCCurrentManifest');
local_write(base_exe, '# fixture exe T015');
mlsc_current_validate('validate_for_execution', pass_config);
fprintf('B5 PASS: wrong executable rejected.\n');

% B6 wrong build manifest: swapped commit (different bytes).
build_b = fullfile(test_root, 'build-b.mat');
local_write_build(build_b, base_runner, pinned, 'fixture-commit-B', prov_fp);
% Re-mint is NOT done: the record still binds the original build file,
% so validating the swapped manifest against the old record must fail.
bad_config = pass_config;
bad_config.current.build_manifest = build_b;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B6 PASS: wrong build manifest rejected.\n');

% B7 wrong resource manifest: same pending marker, different bytes.
resources_b = fullfile(test_root, 'resources-b.mat');
local_write_resources(resources_b, atlas_dir, ...
    't007-gate-a-pending: existence-only; production loadability evidence comes later', ...
    native_names);
tampered_res = load(resources_b);
resources = tampered_res.resources;
resources.extra_note = 'fixture-difference';
save(resources_b, 'resources');
bad_config = pass_config;
bad_config.current.resource_manifest = resources_b;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B7 PASS: wrong resource manifest rejected.\n');

% B8 wrong provenance: record source commit tampered.
gate_a = tampered_rec.gate_a;
gate_a.source_commit = 'tampered-commit';
bad_prov = fullfile(test_root, 'record-badprov.mat');
save(bad_prov, 'gate_a');
bad_config = pass_config;
bad_config.current.gate_a_record = bad_prov;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
gate_a = tampered_rec.gate_a;
gate_a.source_provenance_fingerprint = local_sha_hex(prov_text);
if strcmp(gate_a.source_provenance_fingerprint, ...
        tampered_rec.gate_a.source_provenance_fingerprint)
    gate_a.source_provenance_fingerprint = local_sha_hex(native_a);
end
bad_prov2 = fullfile(test_root, 'record-badprov2.mat');
save(bad_prov2, 'gate_a');
bad_config.current.gate_a_record = bad_prov2;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B8 PASS: wrong provenance rejected.\n');

% B9 wrong MCR root in record.
gate_a = tampered_rec.gate_a;
gate_a.mcr_root = '/tmp/fake-mcr';
bad_mcr = fullfile(test_root, 'record-badmcr.mat');
save(bad_mcr, 'gate_a');
bad_config = pass_config;
bad_config.current.gate_a_record = bad_mcr;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B9 PASS: wrong MCR_ROOT rejected.\n');

% B10 wrong release in record.
gate_a = tampered_rec.gate_a;
gate_a.release = 'R2026b';
bad_release = fullfile(test_root, 'record-badrelease.mat');
save(bad_release, 'gate_a');
bad_config.current.gate_a_record = bad_release;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B10 PASS: wrong release rejected.\n');

% B11 wrong update: recorded actual update differs from disk actual.
gate_a = tampered_rec.gate_a;
gate_a.update_actual = 99;
bad_update = fullfile(test_root, 'record-badupdate.mat');
save(bad_update, 'gate_a');
bad_config.current.gate_a_record = bad_update;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B11 PASS: wrong update rejected.\n');

% B12 wrong arch in record.
gate_a = tampered_rec.gate_a;
gate_a.arch = 'maci64';
bad_arch = fullfile(test_root, 'record-badarch.mat');
save(bad_arch, 'gate_a');
bad_config.current.gate_a_record = bad_arch;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B12 PASS: wrong arch rejected.\n');

% B13 missing-or-failed natives: failed result, mutated file, uncovered
% declared native.
gate_a = tampered_rec.gate_a;
gate_a.native_results = {'fail'; 'pass'};
bad_native = fullfile(test_root, 'record-badnative.mat');
save(bad_native, 'gate_a');
bad_config = pass_config;
bad_config.current.gate_a_record = bad_native;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentNativeEvidence');
local_write(native_b, 'fixture-native-b-MUTATED');
local_assert_error(@() mlsc_current_validate('validate_for_execution', ...
    pass_config));
local_write(native_b, 'fixture-native-b-002');
mlsc_current_validate('validate_for_execution', pass_config);
gate_a = tampered_rec.gate_a;
gate_a.native_names = {'native_a.mexa64'};
gate_a.native_paths = {native_a};
gate_a.native_checksums = {gate_a.native_checksums{1}};
gate_a.native_results = {'pass'};
bad_cover = fullfile(test_root, 'record-badcover.mat');
save(bad_cover, 'gate_a');
bad_config.current.gate_a_record = bad_cover;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentNativeEvidence');
fprintf('B13 PASS: missing-or-failed natives rejected.\n');

% B14 foreign record: minted for a second candidate, used with the first.
runner_b = fullfile(test_root, 'runner-b.sh');
local_write(runner_b, '# foreign runner');
exe_b = fullfile(test_root, 'exe-b');
local_write(exe_b, '# foreign exe');
native_c = fullfile(test_root, 'native_c.mexa64');
local_write(native_c, 'fixture-native-c-003');
build_b2 = fullfile(test_root, 'build-b2.mat');
local_write_build(build_b2, runner_b, pinned, 'fixture-commit-B', prov_fp);
candidate_b = struct('runner', runner_b, 'build_exe', exe_b, ...
    'build_manifest', build_b2, 'resource_manifest', resources_b, ...
    'mcr_root', pinned);
evidence_b = struct('native_names', {{'native_a.mexa64'; 'native_b.mexa64'}}, ...
    'native_paths', {{native_a; native_b}}, ...
    'native_results', {{'pass'; 'pass'}}, ...
    'launcher_result', 'pass', 'runtime_lib_result', 'pass', ...
    'prepare_result', 'pass', 'compute_result', 'pass');
record_b = fullfile(test_root, 'record-b.mat');
mlsc_finalize_gate_a(candidate_b, evidence_b, record_b);
bad_config = pass_config;
bad_config.current.gate_a_record = record_b;
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    bad_config), 'pseudo_CT:MLSCCurrentManifest');
fprintf('B14 PASS: foreign record rejected.\n');

% ------------------------------------------------------------------
% C) Arbitrary strings, fallbacks, legacy, resolver, finalizer.
% ------------------------------------------------------------------
% C1: arbitrary native strings (including old validated markers and
% well-formed-looking forgeries) rejected at contract AND execution.
forged_sha = local_sha_hex(base_runner);
arbitrary_markers = {'t007-gate-a-validated: anything-goes'; ...
    sprintf('t007-gate-a-validated: sha256=%s;provenance=x', forged_sha); ...
    'unknown-fixture-marker'};
for ii = 1:length(arbitrary_markers)
    arb_resources = fullfile(test_root, sprintf('resources-arb-%d.mat', ii));
    local_write_resources(arb_resources, atlas_dir, arbitrary_markers{ii}, {});
    bad_config = base_config;
    bad_config.current.resource_manifest = arb_resources;
    local_assert_error_id(@() mlsc_current_validate('validate_contract', ...
        bad_config), 'pseudo_CT:MLSCCurrentNativeEvidence');
    bad_config.current.gate_a_record = record_path;
    local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
        bad_config), 'pseudo_CT:MLSCCurrentNativeEvidence');
end
fprintf('C1 PASS: arbitrary strings and old markers rejected.\n');

% C2: no basename/size fallback (covered in A3/B5; re-assert shape rule).
assert(~mlsc_sha_shape('bytes=123'), 'Size fallback shape accepted.');
assert(~mlsc_sha_shape('run_mlsc_current_payload.sh'), 'Basename fallback accepted.');
assert(mlsc_sha_shape(forged_sha), 'Valid SHA-256 shape rejected.');
fprintf('C2 PASS: SHA-256 shape rule holds (no basename/size fallback).\n');

% C3: legacy payload fields cannot satisfy the current path.
legacy_subject = struct('subject_id', 't015-legacy-fixture', ...
    'shared_input', fullfile(test_root, 'mprage.nii'), ...
    'shared_temp', test_root);
local_write(fullfile(test_root, 'mprage.nii'), 'fixture');
legacy_runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(test_root, 'job.sh'));
legacy_config = base_config;
legacy_config.mlsc.runner = base_runner;
local_assert_error(@() mlsc_preflight(legacy_subject, legacy_config, ...
    legacy_runtime));
fprintf('C3 PASS: legacy field on current path rejected.\n');

% C4: no legacy/catalog/resolver behavior on the current path.
assert(exist(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_resolve_current_runtime.m'), 'file') ~= 2, ...
    'Catalog/resolver file exists.');
validate_source = local_read(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_current_validate.m'));
assert(isempty(strfind(validate_source, 'mlsc_resolve_current_runtime')), ...
    'Validator implements resolver behavior.');
assert(isempty(strfind(validate_source, 'catalog_root')), ...
    'Validator implements catalog behavior.');
assert(isempty(strfind(validate_source, 't007-gate-a-validated:')), ...
    'Validator still mints free-form markers.');
backend_source = local_read(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_backend.m'));
assert(isempty(strfind(backend_source, 'mlsc_resolve')), ...
    'Backend implements resolver behavior.');
fprintf('C4 PASS: no legacy/catalog/resolver/marker behavior.\n');

% C5: finalizer refuses to self-certify (failed/missing evidence).
bad_evidence = evidence;
bad_evidence.native_results = {'fail'; 'pass'};
local_assert_error(@() mlsc_finalize_gate_a(candidate, bad_evidence, ...
    fullfile(test_root, 'record-should-not-exist.mat')));
bad_evidence2 = rmfield(evidence, 'prepare_result');
local_assert_error(@() mlsc_finalize_gate_a(candidate, bad_evidence2, ...
    fullfile(test_root, 'record-should-not-exist-2.mat')));
assert(exist(fullfile(test_root, 'record-should-not-exist.mat'), ...
    'file') ~= 2, 'Failed evidence minted a record.');
fprintf('C5 PASS: finalizer refuses failed evidence (no self-certify).\n');

% R2010b parse compatibility for touched seams.
parse_targets = {fullfile(root_dir, 'scripts', 'build_mlsc_current.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_validate.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_finalize_gate_a.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_preflight.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_backend.m'); ...
    fullfile(root_dir, 'src', 'config', 'pseudo_CT_load_profile.m'); ...
    fullfile(root_dir, 'src', 'config', 'profiles', 'mlsc_current.m')};
for ii = 1:length(parse_targets)
    try
        mlint(parse_targets{ii});
    catch ME %#ok<NASGU>
        assert(false, 'T015 seam failed to parse.');
    end
end

fprintf('=== MLSC current Gate-A record tests passed: canonical schema, 15 record cases, strict rejection ===\n');
end

function config = local_make_config(test_root, runner_path, pinned, ...
    build_path, resource_path, shell_path, freesurfer_env, record_path)
config = struct();
config.mode = 'mlsc';
config.implementation = 'current';
config.aliasing_default = 0;
config.recenter_before_normalization = 'No';
config.bone_enabled = false;
config.zero_background = 'No';
current = struct('runner', runner_path, 'mcr_root', pinned, ...
    'build_manifest', build_path, 'resource_manifest', resource_path);
if ischar(record_path) && ~isempty(record_path)
    current.gate_a_record = record_path;
end
config.current = current;
config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'shell', shell_path, 'freesurfer_env', freesurfer_env, ...
    'partition', 'basic', 'nodes', 1, 'ntasks', 1, ...
    'cpus_per_task', 1, 'memory', '32G', 'time', '04:00:00');
end

function local_write_build(build_path, runner_path, pinned, commit, prov_fp)
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
build.source_commit = commit;
build.source_provenance_fingerprint = prov_fp;
build.required_outputs = {'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
save(build_path, 'build');
end

function local_write_resources(resource_path, atlas_dir, validation, native_names)
resources = struct();
resources.schema = 'pseudo-CT.mlsc-current-resources/v1';
resources.manifest_version = 1;
resources.atlas_dir = atlas_dir;
resources.native_platform = 'glnxa64';
resources.native_arch = 'glnxa64';
resources.native_validation = validation;
if iscell(native_names) && ~isempty(native_names)
    resources.native_names = native_names(:);
end
save(resource_path, 'resources');
end

function local_assert_manifest_fail(base_config, base_build, test_root, field, value)
tampered = load(base_build);
build = tampered.build;
build.(field) = value;
bad_path = fullfile(test_root, sprintf('build-bad-%s.mat', field));
save(bad_path, 'build');
bad_config = base_config;
bad_config.current.build_manifest = bad_path;
failed = false;
actual_id = '';
try
    mlsc_current_validate('validate_contract', bad_config);
catch ME
    failed = true;
    actual_id = ME.identifier;
end
assert(failed, 'Malformed manifest field did not fail.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCCurrentManifest'), ...
    'Unexpected failure identifier: %s', actual_id);
end

function local_assert_manifest_fail_struct(base_config, base_build, test_root, field, value)
tampered = load(base_build);
build = tampered.build;
build.(field) = value;
bad_path = fullfile(test_root, 'build-bad-struct.mat');
save(bad_path, 'build');
bad_config = base_config;
bad_config.current.build_manifest = bad_path;
failed = false;
actual_id = '';
try
    mlsc_current_validate('validate_contract', bad_config);
catch ME
    failed = true;
    actual_id = ME.identifier;
end
assert(failed, 'Malformed manifest field did not fail.');
assert(strcmp(actual_id, 'pseudo_CT:MLSCCurrentManifest'), ...
    'Unexpected failure identifier: %s', actual_id);
end

function flag = mlsc_sha_shape(value)
flag = false;
try
    if ~ischar(value) || size(value, 1) ~= 1
        return;
    end
    trimmed = strtrim(value);
    if length(trimmed) ~= 64
        return;
    end
    if isempty(regexp(trimmed, '^[0-9a-fA-F]{64}$', 'once'))
        return;
    end
    flag = true;
catch %#ok<CTCH>
    flag = false;
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

function text = local_read(path_name)
fid = fopen(path_name, 'r');
assert(fid ~= -1, 'Source could not be read.');
text = fread(fid, inf, '*char')';
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
    rmdir(directory, 's');
end
end
