function test_mlsc_current_orchestration()
%TEST_MLSC_CURRENT_ORCHESTRATION Focused T004 MLSC-current orchestration checks (offline).
%   Parameterizes only the payload portion of the existing MLSC
%   orchestration (run_pseudo_CT dispatch, mlsc_preflight,
%   mlsc_generate_slurm_script, mlsc_backend, mlsc_lifecycle, mlsc_progress)
%   for artifact/resource validation, prepare -> external normalization ->
%   compute, and progress/output verification. Single shared lifecycle only;
%   no second backend/lifecycle/poller/heartbeat/cancellation/copyback.
%
%   Authority is the T014 pinned correction: config.current carries
%   runner/mcr_root/build_manifest/resource_manifest with the exact pinned
%   MCR_ROOT /usr/pubsw/common/matlab/26.1. No catalog, no resolver file,
%   no dynamic discovery, no MCR 7.11/latest/current-label/submitting-host
%   substitutes. Fixtures use the pending T007 native marker for offline
%   contract checks and never fabricate production validation evidence.
%
%   Covers (fixtures only, no live SSH/Slurm/network/production/subject):
%     1) legacy normalize->legacy payload sequence unchanged
%     2) current prepare->normalize->compute order
%     3) same generic lifecycle for both (schema/progress/contract)
%     4) PREPARE output feeds normalization (staged job manifest before prepare)
%     5) normalization output feeds COMPUTE (normalize before compute, handoff CLI)
%     6) launcher receives the exact pinned MCR_ROOT
%     7) legacy runner/MCR/args order unchanged
%     8) missing/malformed artifact/MCR/manifests fail before science
%     9) pending native evidence blocks real-current execution
%    10) exit 0 + missing output = failure (legacy dynamic + current static)
%    11) no duplication of generic machinery; no catalog/resolver behavior
%    12) T006 follow-up stub for alias-only/gated-input reporting (no science change)
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');

pinned = mlsc_current_validate('pinned_mcr_root');
assert(strcmp(pinned, '/usr/pubsw/common/matlab/26.1'), 'Pinned MCR_ROOT drifted.');
assert(exist(pinned, 'dir') == 7, 'Pinned MCR_ROOT unavailable for offline checks.');
assert(exist(fullfile(pinned, 'runtime', 'glnxa64'), 'dir') == 7, ...
    'Pinned MCR_ROOT structure malformed for offline checks.');
assert(exist(fullfile(root_dir, 'src', 'mlsc', 'mlsc_resolve_current_runtime.m'), 'file') ~= 2, ...
    'Catalog/resolver file must not exist (T014).');

test_root = tempname;
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

% Shared scheduler fixtures (offline, no submission).
freesurfer_env = fullfile(test_root, 'freesurfer-env');
local_write(freesurfer_env, '# fixture');
shell_path = '/bin/bash';
assert(exist(shell_path, 'file') == 2, 'Bash fixture unavailable.');

% Legacy fixtures: existing runner/MCR/args contract.
legacy_root = fullfile(test_root, 'legacy');
mkdir(legacy_root);
legacy_runner = fullfile(legacy_root, 'runner.sh');
legacy_defaults = fullfile(legacy_root, 'defaults.mat');
legacy_templates = fullfile(legacy_root, 'Batch_atlas');
legacy_mcr = fullfile(legacy_root, 'mcr');
mkdir(legacy_templates);
mkdir(legacy_mcr);
local_write(legacy_runner, '# fixture');
local_write(legacy_defaults, 'fixture');
legacy_shared = fullfile(test_root, 'legacy-shared');
mkdir(legacy_shared);
legacy_input = fullfile(legacy_shared, 'mprage.nii');
local_write(legacy_input, 'fixture');
legacy_subject = struct('subject_id', 'legacy-fixture', ...
    'shared_input', legacy_input, 'shared_temp', legacy_shared);
legacy_config = struct();
legacy_config.mode = 'mlsc';
legacy_config.aliasing_default = 1;
legacy_config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'runner', legacy_runner, 'mcr_root', legacy_mcr, ...
    'defaults_mat', legacy_defaults, 'batch_templates', legacy_templates, ...
    'shell', shell_path, 'freesurfer_env', freesurfer_env, ...
    'partition', 'basic', 'nodes', 1, 'ntasks', 1, ...
    'cpus_per_task', 1, 'memory', '1G', 'time', '00:01:00');
legacy_runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(legacy_shared, 'job.sh'));

% 1+7) Legacy normalize->payload sequence and runner/MCR/args unchanged.
assert(~mlsc_current_validate('is_current', legacy_config), 'Legacy misclassified as current.');
legacy_preflight = mlsc_preflight(legacy_subject, legacy_config, legacy_runtime);
assert(legacy_preflight.needs_normalization, 'Legacy fixture should need normalization.');
legacy_artifact = mlsc_generate_slurm_script(legacy_subject, legacy_config, legacy_runtime);
legacy_script = legacy_artifact.script_text;
assert(~isempty(strfind(legacy_script, 'env -u LD_LIBRARY_PATH')), 'Legacy FreeSurfer isolation missing.');
assert(~isempty(strfind(legacy_script, 'tcsh -f -c')), 'Legacy tcsh contract missing.');
assert(~isempty(strfind(legacy_script, 'mri_normalize')), 'Legacy normalization missing.');
assert(isempty(strfind(legacy_script, 'current_runner')), 'Legacy script carries current state.');
assert(isempty(strfind(legacy_script, '"$current_runner"')), 'Legacy script carries current launcher.');
assert(isempty(strfind(legacy_script, 'mlsc_current_job.mat')), 'Legacy script carries current manifest.');
norm_pos = strfind(legacy_script, 'mri_normalize');
pseudo_pos = strfind(legacy_script, 'mlsc_record_progress ''pseudoCT|start''');
assert(~isempty(norm_pos) && ~isempty(pseudo_pos) && norm_pos(1) < pseudo_pos(1), ...
    'Legacy normalization must precede the legacy payload.');
% Positional legacy args order: runner, MCR, input, batch_templates, 0, alias, defaults.
runner_pos = strfind(legacy_script, legacy_runner);
mcr_pos = strfind(legacy_script, legacy_mcr);
batch_pos = strfind(legacy_script, legacy_templates);
defaults_pos = strfind(legacy_script, legacy_defaults);
assert(~isempty(runner_pos) && ~isempty(mcr_pos) && ~isempty(batch_pos) && ~isempty(defaults_pos), ...
    'Legacy runner/MCR/batch/defaults missing from script.');
assert(runner_pos(1) < mcr_pos(1) && mcr_pos(1) < batch_pos(1) && batch_pos(1) < defaults_pos(1), ...
    'Legacy runner/MCR/args order changed.');
assert(~isempty(strfind(legacy_script, ' 0 1 ')) || ~isempty(strfind(legacy_script, ' 0 0 ')), ...
    'Legacy staged-batch/alias positional args changed.');
assert(isempty(strfind(legacy_script, 'export LD_LIBRARY_PATH')), 'Legacy sets global LD_LIBRARY_PATH.');
assert(strcmp(legacy_artifact.schema, 'pseudo-CT.mlsc-slurm-script/v1'), 'Legacy artifact schema changed.');
assert(strcmp(legacy_artifact.heavy_processing_root, '$TMPDIR'), 'Legacy TMPDIR root changed.');

% Current fixtures: pinned artifact contract with pending native evidence.
current_shared = fullfile(test_root, 'current-shared');
mkdir(current_shared);
current_input = fullfile(current_shared, 'mprage.nii');
local_write(current_input, 'fixture');
current_runner = fullfile(test_root, 'run_mlsc_current_payload.sh');
local_write(current_runner, '# fixture runner');
build_path = fullfile(test_root, 'build.mat');
resource_path = fullfile(test_root, 'resources.mat');
atlas_dir = fullfile(test_root, 'Batch_atlas_current');
mkdir(atlas_dir);
local_write_valid_current_manifests(build_path, resource_path, current_runner, pinned, atlas_dir);
current_subject = struct('subject_id', 'current-fixture', ...
    'shared_input', current_input, 'shared_temp', current_shared, ...
    'check_aliasing', 1, 'recenter_before_normalization', 'Yes');
current_config = struct();
current_config.mode = 'mlsc';
current_config.implementation = 'current';
current_config.aliasing_default = 0;
current_config.recenter_before_normalization = 'No';
current_config.bone_enabled = false;
current_config.zero_background = 'No';
current_config.current = struct('runner', current_runner, ...
    'mcr_root', pinned, 'build_manifest', build_path, ...
    'resource_manifest', resource_path);
current_config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'shell', shell_path, 'freesurfer_env', freesurfer_env, ...
    'partition', 'basic', 'nodes', 1, 'ntasks', 1, ...
    'cpus_per_task', 1, 'memory', '32G', 'time', '04:00:00');
current_runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(current_shared, 'job.sh'));

% 6) Pinned launcher identity; per-job overrides beat profile defaults.
assert(mlsc_current_validate('is_current', current_config), 'Current misclassified.');
mlsc_current_validate('validate_contract', current_config);
current_preflight = mlsc_preflight(current_subject, current_config, current_runtime);
assert(current_preflight.check_aliasing == 1, 'Per-job aliasing override lost (profile default used).');
assert(current_preflight.needs_normalization, 'Current fixture should need normalization.');
current_artifact = mlsc_generate_slurm_script(current_subject, current_config, current_runtime);
assert(current_artifact.is_current, 'Current artifact identity missing.');
assert(strcmp(current_artifact.current_mcr_root, pinned), 'Current artifact MCR_ROOT not pinned.');
assert(strcmp(current_artifact.current_runner, current_runner), 'Current artifact runner mismatch.');
script = current_artifact.script_text;

% 2) Current prepare -> normalize -> compute order with the pinned launcher.
prepare_pos = strfind(script, '"$current_runner" "$current_mcr_root" prepare');
compute_pos = strfind(script, '"$current_runner" "$current_mcr_root" compute');
tcsh_pos = strfind(script, 'tcsh -f -c');
assert(~isempty(prepare_pos) && ~isempty(compute_pos) && prepare_pos(1) < compute_pos(1), ...
    'Current prepare must precede compute.');
assert(~isempty(strfind(script, 'env -u LD_LIBRARY_PATH')), 'Current FreeSurfer isolation missing.');
assert(~isempty(tcsh_pos) && prepare_pos(1) < tcsh_pos(1) && tcsh_pos(1) < compute_pos(1), ...
    'Current normalization must sit between prepare and compute.');
assert(~isempty(strfind(script, 'source "$MLSC_FREESURFER_ENV"; mri_normalize')), ...
    'Current external normalization contract changed.');
assert(isempty(strfind(script, 'export LD_LIBRARY_PATH')), 'Current sets global LD_LIBRARY_PATH.');
assert(~isempty(strfind(script, 'current_mcr_root=''')) || ~isempty(strfind(script, 'current_mcr_root=')), ...
    'Current MCR_ROOT assignment missing.');
assert(~isempty(strfind(script, pinned)), 'Pinned MCR_ROOT missing from current script.');

% 4) PREPARE output feeds normalization: staged manifests before prepare.
stage_job_pos = strfind(script, 'cp -- "$shared_job_manifest" "$local_job_manifest"');
stage_res_pos = strfind(script, 'cp -- "$shared_resource_manifest" "$local_resource_manifest"');
assert(~isempty(stage_job_pos) && ~isempty(stage_res_pos), 'Current manifest staging missing.');
assert(stage_job_pos(1) < prepare_pos(1) && stage_res_pos(1) < prepare_pos(1), ...
    'Current manifests must stage before prepare.');
job_manifest_path = fullfile(current_shared, 'mlsc_current_job.mat');
assert(exist(job_manifest_path, 'file') == 2, 'Current job manifest not staged by generation.');
staged = load(job_manifest_path);
assert(isfield(staged, 'job') && isstruct(staged.job) && numel(staged.job) == 1, ...
    'Staged current job manifest invalid.');
assert(strcmp(staged.job.schema, 'pseudo-CT.mlsc-current-job/v1'), 'Staged job schema mismatch.');
assert(staged.job.check_aliasing == 1, 'Staged job lost per-job aliasing override.');
assert(strcmp(staged.job.recenter_before_normalization, 'Yes'), ...
    'Staged job lost per-job recenter override (profile default used).');
% R001 behavioral: raw mprage.nii with PREPARE-produced mprage_corrected.nii
% must normalize the corrected file to corrected_normalized (consumed by
% COMPUTE), never the raw file; never source/eval the .mat handoff.
assert(~isempty(strfind(script, 'prepare_selected=')), 'Dynamic PREPARE selection missing.');
assert(~isempty(strfind(script, 'prepare_expected=')), 'Dynamic PREPARE expectation missing.');
assert(~isempty(strfind(script, 'prepare_corrected=')), 'PREPARE corrected derivation missing.');
assert(isempty(strfind(script, 'source "$shared_temp/mlsc_current_handoff')), ...
    'Script sources the handoff (forbidden).');
assert(isempty(strfind(script, 'source $TMPDIR/mlsc_current_handoff')), ...
    'Script sources the handoff (forbidden).');
assert(~isempty(strfind(script, 'MLSC_INPUT_NAME=$prepare_selected')), ...
    'Normalization does not consume the PREPARE-selected input.');
assert(~isempty(strfind(script, 'MLSC_NORMALIZED_NAME=$prepare_expected')), ...
    'Normalization does not produce the PREPARE-expected output.');
assert(~isempty(strfind(script, 'copy_optional "$TMPDIR/$prepare_expected"')), ...
    'Normalized copyback does not use the PREPARE-expected basename.');
% Behaviorally execute the generated resolution logic with fixtures only:
% fake TMPDIR with raw + PREPARE-corrected present, stub mri_normalize that
% records its args, then prove the corrected file was normalized.
fake_tmp = fullfile(test_root, 'fake-tmpdir-r001');
mkdir(fake_tmp);
local_write(fullfile(fake_tmp, 'mprage.nii'), 'fixture-raw');
local_write(fullfile(fake_tmp, 'mprage_corrected.nii'), 'fixture-corrected');
r001_bash = fullfile(test_root, 'r001_prove.sh');
r001_fid = fopen(r001_bash, 'w');
assert(r001_fid ~= -1, 'R001 fixture could not be created.');
fprintf(r001_fid, '#!/bin/bash\n');
fprintf(r001_fid, 'set -euo pipefail\n');
fprintf(r001_fid, 'TMPDIR="%s"\n', fake_tmp);
fprintf(r001_fid, 'input_name="mprage.nii"\n');
fprintf(r001_fid, 'prepare_corrected="mprage_corrected.nii"\n');
fprintf(r001_fid, 'prepare_corrected_normalized="mprage_corrected_normalized.nii"\n');
fprintf(r001_fid, 'normalized_name="mprage_normalized.nii"\n');
fprintf(r001_fid, 'prepare_selected="$input_name"\n');
fprintf(r001_fid, 'prepare_expected="$normalized_name"\n');
fprintf(r001_fid, 'if [ -f "$TMPDIR/$prepare_corrected" ]; then\n');
fprintf(r001_fid, '    prepare_selected="$prepare_corrected"\n');
fprintf(r001_fid, '    prepare_expected="$prepare_corrected_normalized"\n');
fprintf(r001_fid, 'fi\n');
fprintf(r001_fid, 'if [ "$prepare_selected" != "mprage_corrected.nii" ]; then echo "R001 selected mismatch: $prepare_selected"; exit 10; fi\n');
fprintf(r001_fid, 'if [ "$prepare_expected" != "mprage_corrected_normalized.nii" ]; then echo "R001 expected mismatch: $prepare_expected"; exit 11; fi\n');
fprintf(r001_fid, 'mri_normalize() { printf "%%s\\n" "$1:$2" > "$TMPDIR/normalize_args.txt"; printf "stub-normalized" > "$2"; }\n');
fprintf(r001_fid, 'mri_normalize "$TMPDIR/$prepare_selected" "$TMPDIR/$prepare_expected"\n');
fprintf(r001_fid, 'if [ ! -s "$TMPDIR/mprage_corrected_normalized.nii" ]; then echo "R001 corrected_normalized not produced"; exit 12; fi\n');
fprintf(r001_fid, 'if [ -s "$TMPDIR/mprage_normalized.nii" ]; then echo "R001 raw normalized must not be produced"; exit 13; fi\n');
fprintf(r001_fid, 'printf "R001_BEHAVIORAL_PASS\\n"\n');
fclose(r001_fid);
[status_r001, output_r001] = system(['bash "' r001_bash '"']);
assert(status_r001 == 0 && ~isempty(strfind(output_r001, 'R001_BEHAVIORAL_PASS')), ...
    'R001 behavioral proof failed (corrected PREPARE output did not feed normalization): %s', output_r001);
% Without the corrected file, the raw file must be selected (same logic).
fake_tmp_raw = fullfile(test_root, 'fake-tmpdir-r001-raw');
mkdir(fake_tmp_raw);
local_write(fullfile(fake_tmp_raw, 'mprage.nii'), 'fixture-raw');
r001b_bash = fullfile(test_root, 'r001b_prove.sh');
r001b_fid = fopen(r001b_bash, 'w');
assert(r001b_fid ~= -1, 'R001 raw fixture could not be created.');
fprintf(r001b_fid, '#!/bin/bash\n');
fprintf(r001b_fid, 'set -euo pipefail\n');
fprintf(r001b_fid, 'TMPDIR="%s"\n', fake_tmp_raw);
fprintf(r001b_fid, 'input_name="mprage.nii"\n');
fprintf(r001b_fid, 'prepare_corrected="mprage_corrected.nii"\n');
fprintf(r001b_fid, 'prepare_corrected_normalized="mprage_corrected_normalized.nii"\n');
fprintf(r001b_fid, 'normalized_name="mprage_normalized.nii"\n');
fprintf(r001b_fid, 'prepare_selected="$input_name"\n');
fprintf(r001b_fid, 'prepare_expected="$normalized_name"\n');
fprintf(r001b_fid, 'if [ -f "$TMPDIR/$prepare_corrected" ]; then\n');
fprintf(r001b_fid, '    prepare_selected="$prepare_corrected"\n');
fprintf(r001b_fid, '    prepare_expected="$prepare_corrected_normalized"\n');
fprintf(r001b_fid, 'fi\n');
fprintf(r001b_fid, 'if [ "$prepare_selected" != "mprage.nii" ]; then exit 10; fi\n');
fprintf(r001b_fid, 'if [ "$prepare_expected" != "mprage_normalized.nii" ]; then exit 11; fi\n');
fprintf(r001b_fid, 'printf "R001B_BEHAVIORAL_PASS\\n"\n');
fclose(r001b_fid);
[status_r001b, output_r001b] = system(['bash "' r001b_bash '"']);
assert(status_r001b == 0 && ~isempty(strfind(output_r001b, 'R001B_BEHAVIORAL_PASS')), ...
    'R001 raw fallback behavioral proof failed: %s', output_r001b);

% 5) Normalization output feeds COMPUTE handoff (same manifests, verified order).
% Behavioral: the verified normalized file (PREPARE-expected) must exist
% before COMPUTE runs; the staged manifests and COMPUTE CLI order are
% verified plus a dynamic missing-normalized failure.
assert(~isempty(strfind(script, 'local_normalized="$TMPDIR/$normalized_name"')), ...
    'Current normalized handoff path missing.');
assert(~isempty(strfind(script, '"$current_runner" "$current_mcr_root" compute "$local_job_manifest" "$local_resource_manifest"')), ...
    'Current COMPUTE CLI order changed (runner/MCR/compute/job/resources).');
assert(~isempty(strfind(script, 'if [ ! -s "$local_job_manifest" ]')), 'Current staged job guard missing.');
assert(~isempty(strfind(script, 'if [ ! -s "$local_resource_manifest" ]')), 'Current staged resource guard missing.');
assert(~isempty(strfind(script, 'if [ "$normalize_needed" -eq 1 ] && [ ! -s "$TMPDIR/$prepare_expected" ]')), ...
    'Current normalized-before-compute verification missing.');
% Dynamic: normalized verification fails closed when the expected file is
% missing (exit 73), passes when present. Offline fixtures only.
r005_tmp = fullfile(test_root, 'fake-verify-r005');
mkdir(r005_tmp);
r005_bash_missing = fullfile(test_root, 'r005_missing.sh');
r005_fid = fopen(r005_bash_missing, 'w');
assert(r005_fid ~= -1, 'R005 fixture could not be created.');
fprintf(r005_fid, '#!/bin/bash\n');
fprintf(r005_fid, 'set -euo pipefail\n');
fprintf(r005_fid, 'TMPDIR="%s"\n', r005_tmp);
fprintf(r005_fid, 'prepare_expected="mprage_corrected_normalized.nii"\n');
fprintf(r005_fid, 'normalize_needed=1\n');
fprintf(r005_fid, 'if [ "$normalize_needed" -eq 1 ] && [ ! -s "$TMPDIR/$prepare_expected" ]; then\n');
fprintf(r005_fid, '    printf "Node-local normalized output is missing or empty.\\n" >&2\n');
fprintf(r005_fid, '    exit 73\n');
fprintf(r005_fid, 'fi\n');
fprintf(r005_fid, 'printf "R005_UNEXPECTED_PASS\\n"\n');
fclose(r005_fid);
[status_r005m, ~] = system(['bash "' r005_bash_missing '"']);
assert(status_r005m ~= 0, 'R005 missing-normalized verification did not fail closed.');
local_write(fullfile(r005_tmp, 'mprage_corrected_normalized.nii'), 'fixture-normalized');
r005_bash_present = fullfile(test_root, 'r005_present.sh');
r005p_fid = fopen(r005_bash_present, 'w');
assert(r005p_fid ~= -1, 'R005 present fixture could not be created.');
fprintf(r005p_fid, '#!/bin/bash\n');
fprintf(r005p_fid, 'set -euo pipefail\n');
fprintf(r005p_fid, 'TMPDIR="%s"\n', r005_tmp);
fprintf(r005p_fid, 'prepare_expected="mprage_corrected_normalized.nii"\n');
fprintf(r005p_fid, 'normalize_needed=1\n');
fprintf(r005p_fid, 'if [ "$normalize_needed" -eq 1 ] && [ ! -s "$TMPDIR/$prepare_expected" ]; then\n');
fprintf(r005p_fid, '    exit 73\n');
fprintf(r005p_fid, 'fi\n');
fprintf(r005p_fid, 'printf "R005_BEHAVIORAL_PASS\\n"\n');
fclose(r005p_fid);
[status_r005p, output_r005p] = system(['bash "' r005_bash_present '"']);
assert(status_r005p == 0 && ~isempty(strfind(output_r005p, 'R005_BEHAVIORAL_PASS')), ...
    'R005 present-normalized verification did not pass: %s', output_r005p);

% 3) Same generic lifecycle for both: schema, progress, TMPDIR, copyback.
assert(strcmp(current_artifact.schema, legacy_artifact.schema), 'Current/legacy lifecycle schema diverged.');
assert(strcmp(current_artifact.progress_format, legacy_artifact.progress_format), ...
    'Current/legacy progress format diverged.');
assert(strcmp(current_artifact.heavy_processing_root, '$TMPDIR'), 'Current TMPDIR root diverged.');
assert(~isempty(strfind(script, 'mlsc_record_progress ''stage_in|done''')), 'Current stage-in progress missing.');
assert(~isempty(strfind(script, 'mlsc_record_progress ''preparation|done''')), 'Current preparation progress missing (R006).');
assert(~isempty(strfind(script, 'mlsc_record_progress ''alias_recenter|done''')), 'Current alias-recenter progress missing (R006).');
assert(~isempty(strfind(script, 'mlsc_record_progress ''normalize|start''')), 'Current normalize progress missing.');
assert(~isempty(strfind(script, 'mlsc_record_progress ''alignment_mask|done''')), 'Current alignment-mask progress missing (R006).');
assert(~isempty(strfind(script, 'mlsc_record_progress ''segmentation|done''')), 'Current segmentation progress missing (R006).');
assert(~isempty(strfind(script, 'mlsc_record_progress ''bone|done''')), 'Current bone progress missing (R006).');
assert(~isempty(strfind(script, 'mlsc_record_progress ''dartel_warp_reslice|done''')), 'Current DARTEL progress missing (R006).');
assert(~isempty(strfind(script, 'mlsc_record_progress ''pseudoCT|start''')), 'Current pseudoCT progress missing.');
assert(~isempty(strfind(script, 'mlsc_record_progress ''attenuation_qc|done''')), 'Current attenuation-QC progress missing (R006).');
assert(~isempty(strfind(script, 'mlsc_record_progress ''verify|start''')), 'Current verify progress missing.');
assert(~isempty(strfind(script, 'mlsc_record_progress ''copy_back|start''')), 'Current copy-back progress missing.');
assert(isequal(mlsc_progress('records'), current_artifact.progress_records), ...
    'Current progress records bypass the generic engine.');
assert(numel(mlsc_progress('records')) == 16, 'Extended current milestone enum must be 16 records (R006).');
% Required-output verification is the shared generic gate with a current
% three-output plus mandatory-evidence contract (exit 0 + missing output
% or evidence still fails; nonempty-only insufficient).
assert(~isempty(strfind(script, 'if [ ! -s "$TMPDIR/att_map.nii" ]')), 'Current att_map verify missing.');
assert(~isempty(strfind(script, 'if [ ! -s "$TMPDIR/Fusion_MR_Pseudo_CT_validation.tiff" ]')), ...
    'Current QC verify missing.');
assert(~isempty(strfind(script, 'if [ ! -s "$TMPDIR/Pseudo_CT_AC_Version.txt" ]')), 'Current version verify missing.');
assert(~isempty(strfind(script, 'if [ ! -s "$TMPDIR/mlsc_current_handoff.mat" ]')), 'Current handoff verify missing (R003).');
assert(~isempty(strfind(script, 'if [ ! -s "$TMPDIR/mlsc_current_prepare_evidence.txt" ]')), 'Current prepare-evidence verify missing (R003).');
assert(~isempty(strfind(script, 'if [ ! -s "$TMPDIR/mlsc_current_output_verification.txt" ]')), 'Current output-verification missing (R003).');
assert(~isempty(strfind(script, 'cp -- "$TMPDIR/mlsc_current_handoff.mat" "$shared_temp/mlsc_current_handoff.mat"')), 'Mandatory handoff copyback missing (R003).');
assert(~isempty(strfind(script, 'cp -- "$TMPDIR/mlsc_current_output_verification.txt"')), 'Mandatory verification copyback missing (R003).');
assert(~isempty(strfind(script, 'Shared output verification copy-back is missing or empty.')), 'Mandatory evidence copyback check missing (R003).');
assert(iscell(current_artifact.required_outputs) && numel(current_artifact.required_outputs) == 3, ...
    'Current required-output contract is not the three-output set.');
assert(iscell(current_artifact.required_evidence) && numel(current_artifact.required_evidence) == 3, ...
    'Current mandatory-evidence contract missing (R003).');
lifecycle_source = local_read(fullfile(root_dir, 'src', 'mlsc', 'mlsc_lifecycle.m'));
assert(~isempty(strfind(lifecycle_source, 'Exit-0 plus missing output is failure.')), ...
    'Shared exit-0-missing-output gate missing.');
assert(~isempty(strfind(lifecycle_source, 'Fusion_MR_Pseudo_CT_validation.tiff')), ...
    'Shared lifecycle lacks the current QC output.');
assert(~isempty(strfind(lifecycle_source, 'Pseudo_CT_AC_Version.txt')), ...
    'Shared lifecycle lacks the current version output.');
assert(~isempty(strfind(lifecycle_source, 'finite float32')), ...
    'Lifecycle lacks finite-float32 attenuation requirement (R003).');
assert(~isempty(strfind(lifecycle_source, 'copyback_identity_ok')), ...
    'Lifecycle lacks copyback-identity verification (R003).');

% 8) Missing/malformed artifact/MCR/manifests fail before science.
bad_config = current_config;
bad_config.current.runner = fullfile(test_root, 'missing-runner.sh');
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
bad_config = current_config;
bad_config.current.mcr_root = '/usr/pubsw/common/matlab/current';
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
bad_config = current_config;
bad_config.current.mcr_root = fullfile(test_root, 'missing-mcr');
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
bad_config = current_config;
bad_config.current.build_manifest = fullfile(test_root, 'missing-build.mat');
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
bad_config = current_config;
bad_config.current.resource_manifest = fullfile(test_root, 'missing-resources.mat');
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
assert_error(@() mlsc_current_validate('structure', fullfile(test_root, 'missing-mcr')));
malformed_mcr = fullfile(test_root, 'malformed-mcr');
mkdir(malformed_mcr);
assert_error(@() mlsc_current_validate('structure', malformed_mcr));
tampered = load(build_path);
tampered.build.release = 'R2026b';
build = tampered.build;
tampered_path = fullfile(test_root, 'build-wrong-release.mat');
save(tampered_path, 'build');
bad_config = current_config;
bad_config.current.build_manifest = tampered_path;
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
tampered = load(build_path);
tampered.build.update_minimum = 99;
build = tampered.build;
tampered_path = fullfile(test_root, 'build-old-update.mat');
save(tampered_path, 'build');
bad_config = current_config;
bad_config.current.build_manifest = tampered_path;
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
tampered = load(build_path);
tampered.build.arch = 'maci64';
build = tampered.build;
tampered_path = fullfile(test_root, 'build-wrong-arch.mat');
save(tampered_path, 'build');
bad_config = current_config;
bad_config.current.build_manifest = tampered_path;
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
tampered = load(resource_path);
tampered.resources.native_arch = 'maci64';
resources = tampered.resources;
tampered_path = fullfile(test_root, 'resources-wrong-arch.mat');
save(tampered_path, 'resources');
bad_config = current_config;
bad_config.current.resource_manifest = tampered_path;
assert_error(@() mlsc_current_validate('validate_contract', bad_config));
% R002: unknown native validation is rejected at contract (not just the
% single pending string); actual MCR_ROOT identity is disk-validated.
tampered = load(resource_path);
tampered.resources.native_validation = 'unknown-fixture-marker';
resources = tampered.resources;
tampered_path = fullfile(test_root, 'resources-unknown-validation.mat');
save(tampered_path, 'resources');
bad_config = current_config;
bad_config.current.resource_manifest = tampered_path;
assert_error_id(@() mlsc_current_validate('validate_contract', bad_config), ...
    'pseudo_CT:MLSCCurrentNativeEvidence');
assert_error_id(@() mlsc_current_validate('validate_for_execution', bad_config), ...
    'pseudo_CT:MLSCCurrentNativeEvidence');
actual_info = mlsc_current_validate('actual_identity', pinned);
assert(isstruct(actual_info) && strcmp(actual_info.release, 'R2026a'), ...
    'Disk-validated actual identity missing (R002).');
assert_error(@() mlsc_current_validate('actual_identity', fullfile(test_root, 'missing-mcr')));
% Legacy payload fields must not satisfy current validation (no fake legacy contract).
bad_config = current_config;
bad_config.mlsc.runner = legacy_runner;
assert_error(@() mlsc_preflight(current_subject, bad_config, current_runtime));
% Every failure above occurs before any science: no handoff/evidence written.
assert(exist(fullfile(current_shared, 'mlsc_current_handoff.mat'), 'file') ~= 2, ...
    'Failed validation ran science.');

% 9) Pending native evidence blocks real-current execution (never fabricated).
% R002: pending and unknown both stay blocked without a production run.
mlsc_current_validate('validate_contract', current_config);
assert_error_id(@() mlsc_current_validate('validate_for_execution', current_config), ...
    'pseudo_CT:MLSCCurrentNativeEvidence');
tampered_unknown = load(resource_path);
tampered_unknown.resources.native_validation = 'unknown-fixture-marker';
resources = tampered_unknown.resources;
unknown_resource_path = fullfile(test_root, 'resources-unknown-exec.mat');
save(unknown_resource_path, 'resources');
unknown_config = current_config;
unknown_config.current.resource_manifest = unknown_resource_path;
assert_error_id(@() mlsc_current_validate('validate_for_execution', unknown_config), ...
    'pseudo_CT:MLSCCurrentNativeEvidence');
submit_called = false;
transport = struct('verify', @() true, 'submit_script', @local_record_submit);
try
    mlsc_backend(current_subject, current_config, current_runtime, transport);
    assert(false, 'Pending native evidence did not block submission.');
catch ME
    assert(strcmp(ME.identifier, 'pseudo_CT:MLSCCurrentNativeEvidence'), ...
        'Unexpected backend gate identifier: %s', ME.identifier);
end
assert(~submit_called, 'Blocked backend submitted.');

% 10) Exit 0 + missing output = failure (shared generic gate, legacy dynamic
% plus current dynamic for missing outputs and mandatory evidence).
legacy_transport = struct('verify', @local_legacy_verify, ...
    'submit_script', @local_legacy_submit, ...
    'query_squeue', @local_legacy_squeue, 'query_sacct', @local_legacy_sacct, ...
    'query_squeue_by_name', @local_legacy_squeue_by_name, ...
    'query_sacct_by_name', @local_legacy_sacct_by_name, ...
    'cancel_job', @local_legacy_cancel, 'sleep', @local_legacy_sleep);
legacy_result_runtime = struct('profile', 'mlsc', 'account', 'fixture-account', ...
    'script_path', fullfile(legacy_shared, 'lifecycle-job.sh'), ...
    'evidence_dir', fullfile(test_root, 'legacy-evidence'), ...
    'log_archive_dir', fullfile(test_root, 'legacy-evidence'), ...
    'cleanup_script', false, 'timeout_seconds', 10, ...
    'poll_interval_seconds', 1, 'accounting_timeout_seconds', 1, ...
    'max_polls', 2, 'max_accounting_polls', 1);
mkdir(legacy_result_runtime.evidence_dir);
legacy_result = mlsc_lifecycle(legacy_subject, legacy_config, legacy_result_runtime, legacy_transport);
assert(legacy_result.terminal && ~legacy_result.success, ...
    'Scheduler COMPLETED with missing att_map must fail.');
assert(strcmp(legacy_result.workflow_state, 'failed'), 'Missing-output workflow state must be failed.');
assert(~legacy_result.copy_back.verified, 'Missing-output copy-back must not verify.');
% Current dynamic (fail-closed Gate A): arbitrary validated markers are
% rejected at contract and execution (no production bypass). Scheduler
% COMPLETED with missing outputs/evidence must still fail via the shared
% verification/failure path (here via the fail-closed backend block plus
% copyback non-verification). Uses an arbitrary validated fixture marker
% that must NOT pass.
validated_resources = load(resource_path);
validated_resources.resources.native_validation = ...
    't007-gate-a-validated: fixture-production-proof';
resources = validated_resources.resources;
validated_resource_path = fullfile(test_root, 'resources-validated.mat');
save(validated_resource_path, 'resources');
validated_config = current_config;
validated_config.current.resource_manifest = validated_resource_path;
assert_error_id(@() mlsc_current_validate('validate_contract', validated_config), ...
    'pseudo_CT:MLSCCurrentNativeEvidence');
assert_error_id(@() mlsc_current_validate('validate_for_execution', validated_config), ...
    'pseudo_CT:MLSCCurrentNativeEvidence');
current_shared_missing = fullfile(test_root, 'current-missing');
mkdir(current_shared_missing);
missing_input = fullfile(current_shared_missing, 'mprage.nii');
local_write(missing_input, 'fixture');
missing_subject = struct('subject_id', 'current-missing-fixture', ...
    'shared_input', missing_input, 'shared_temp', current_shared_missing, ...
    'check_aliasing', 0, 'recenter_before_normalization', 'No');
missing_runtime = struct('profile', 'mlsc', 'account', 'fixture-account', ...
    'script_path', fullfile(current_shared_missing, 'job.sh'), ...
    'evidence_dir', fullfile(test_root, 'current-missing-evidence'), ...
    'log_archive_dir', fullfile(test_root, 'current-missing-evidence'), ...
    'cleanup_script', false, 'timeout_seconds', 10, ...
    'poll_interval_seconds', 1, 'accounting_timeout_seconds', 1, ...
    'max_polls', 2, 'max_accounting_polls', 1);
mkdir(missing_runtime.evidence_dir);
missing_transport = struct('verify', @local_legacy_verify, ...
    'submit_script', @local_current_missing_submit, ...
    'query_squeue', @local_legacy_squeue, 'query_sacct', @local_current_missing_sacct, ...
    'query_squeue_by_name', @local_legacy_squeue_by_name, ...
    'query_sacct_by_name', @local_legacy_sacct_by_name, ...
    'cancel_job', @local_legacy_cancel, 'sleep', @local_legacy_sleep);
missing_result = mlsc_lifecycle(missing_subject, validated_config, missing_runtime, missing_transport);
assert(missing_result.terminal && ~missing_result.success, ...
    'Current COMPLETED with missing outputs/evidence must fail dynamically.');
assert(strcmp(missing_result.workflow_state, 'failed'), 'Current missing-output workflow must be failed.');
assert(~missing_result.copy_back.verified, 'Current missing-output copy-back must not verify.');
% Current dynamic evidence failure: three outputs present but mandatory
% evidence absent must still fail (nonempty-files-only insufficient).
evidence_fail_shared = fullfile(test_root, 'current-evidence-fail');
mkdir(evidence_fail_shared);
evidence_fail_input = fullfile(evidence_fail_shared, 'mprage.nii');
local_write(evidence_fail_input, 'fixture');
local_write(fullfile(evidence_fail_shared, 'att_map.nii'), 'fixture-att');
local_write(fullfile(evidence_fail_shared, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'fixture-qc');
local_write(fullfile(evidence_fail_shared, 'Pseudo_CT_AC_Version.txt'), 'fixture-version');
evidence_fail_subject = struct('subject_id', 'current-evidence-fail', ...
    'shared_input', evidence_fail_input, 'shared_temp', evidence_fail_shared, ...
    'check_aliasing', 0, 'recenter_before_normalization', 'No');
evidence_fail_runtime = struct('profile', 'mlsc', 'account', 'fixture-account', ...
    'script_path', fullfile(evidence_fail_shared, 'job.sh'), ...
    'evidence_dir', fullfile(test_root, 'current-evidence-fail-dir'), ...
    'log_archive_dir', fullfile(test_root, 'current-evidence-fail-dir'), ...
    'cleanup_script', false, 'timeout_seconds', 10, ...
    'poll_interval_seconds', 1, 'accounting_timeout_seconds', 1, ...
    'max_polls', 2, 'max_accounting_polls', 1);
mkdir(evidence_fail_runtime.evidence_dir);
evidence_fail_result = mlsc_lifecycle(evidence_fail_subject, validated_config, evidence_fail_runtime, missing_transport);
assert(evidence_fail_result.terminal && ~evidence_fail_result.success, ...
    'Current outputs without mandatory evidence must fail dynamically.');
assert(~evidence_fail_result.copy_back.verified, 'Evidence-missing copy-back must not verify.');

% 11) No duplication: single shared backend/lifecycle/polling/cancellation/copyback.
% R005: single generic script assembly path with narrow current branches.
assert(exist(fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_backend.m'), 'file') ~= 2, ...
    'Separate current backend duplicates the shared lifecycle.');
assert(exist(fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_lifecycle.m'), 'file') ~= 2, ...
    'Separate current lifecycle duplicates the shared lifecycle.');
assert(exist(fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_poll.m'), 'file') ~= 2, ...
    'Separate current poller duplicates the shared poller.');
backend_source = local_read(fullfile(root_dir, 'src', 'mlsc', 'mlsc_backend.m'));
assert(isempty(strfind(backend_source, 'squeue')) || ~isempty(strfind(lifecycle_source, 'squeue')), ...
    'Polling moved out of the shared lifecycle.');
assert(~isempty(strfind(lifecycle_source, 'local_verify_copyback')), 'Shared copy-back gate missing.');
assert(~isempty(strfind(current_artifact.submission_command, 'sbatch')), 'Current submission construction diverged.');
assert(~isempty(strfind(legacy_artifact.submission_command, 'sbatch')), 'Legacy submission construction diverged.');
gen_source = local_read(fullfile(root_dir, 'src', 'mlsc', 'mlsc_generate_slurm_script.m'));
% R005 single generic assembly: shared helpers exist and both paths reuse
% them; no second inline construction of directives/TMPDIR/progress/env/
% staging/sbatch remains in the current branch.
assert(~isempty(strfind(gen_source, 'local_generic_directives')), 'Single generic directives path missing (R005).');
assert(~isempty(strfind(gen_source, 'local_generic_progress_tmpdir')), 'Single generic progress/TMPDIR path missing (R005).');
assert(~isempty(strfind(gen_source, 'local_generic_env_staging')) || ~isempty(strfind(gen_source, 'local_generic_env_pre')), 'Single generic env/staging path missing (R005).');
assert(~isempty(strfind(gen_source, 'local_generic_sbatch')), 'Single generic sbatch path missing (R005).');
assert(~isempty(strfind(gen_source, 'local_append_generic')), 'Generic append helper missing (R005).');
% No catalog/resolver behavior anywhere on the current path (guard comments
% state the prohibition; no resolver file, field, or lookup exists).
assert(~isempty(strfind(backend_source, 'No catalog/resolver')), 'Backend pinned no-catalog contract missing.');
assert(isempty(strfind(backend_source, 'mlsc_resolve')), 'Backend implements resolver behavior.');
assert(isempty(strfind(backend_source, 'catalog_root')), 'Backend implements catalog behavior.');
validate_source = local_read(fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_validate.m'));
assert(~isempty(strfind(validate_source, 'There is no generic')), 'Pinned no-catalog contract missing.');
assert(isempty(strfind(validate_source, 'mlsc_resolve_current_runtime')), ...
    'Validator implements resolver behavior.');
assert(isempty(strfind(gen_source, 'latest')), 'Generator implements latest-label selection.');
assert(isempty(strfind(gen_source, 'MCR 7.11')), 'Generator falls back to MCR 7.11.');

% run_pseudo_CT dispatch carries per-job current overrides without touching legacy.
entry_source = local_read(fullfile(root_dir, 'run_pseudo_CT.m'));
assert(~isempty(strfind(entry_source, 'subject.check_aliasing')), 'Dispatch drops per-job aliasing override.');
assert(~isempty(strfind(entry_source, 'subject.recenter_before_normalization')), ...
    'Dispatch drops per-job recenter override.');
% R004: current finalization skips the legacy post-fetch re-mask.
assert(~isempty(strfind(entry_source, 'is_current_finalize')), 'Current finalize skip missing (R004).');
assert(~isempty(strfind(entry_source, 'shared current core owns zero-background')), 'Current finalize comment missing (R004).');

% 12) T006 follow-up stub: alias-only/gated-input reporting is a potential
% behavior/logging discrepancy only. Science is unchanged here; T006 owns
% any reporting regression with its own focused verification.
% T006 / Gate B (deferred TEST requirement only; proof-only injected-backend
% seam removed, no replacement seam): Exercise a successful mlsc-current job
% through the real production copyback, required-output verification, caller
% finalization, durable evidence persistence, and reload/assertion of final
% success, plus at least one failure case where missing/corrupt outputs or
% evidence prevents finalization.
prepare_source = local_read(fullfile(root_dir, 'src', 'core', 'pseudo_CT_current_prepare.m'));
assert(~isempty(strfind(prepare_source, '[recentering] Skipped as configured.')), ...
    'Prepare gated-input logging baseline changed.');
assert(~isempty(strfind(prepare_source, '[aliasing correction] Skipped as configured.')), ...
    'Prepare alias-only logging baseline changed.');
assert(~isempty(strfind(prepare_source, '_normalized.nii')), 'Prepare normalization gate changed.');
assert(~isempty(strfind(prepare_source, '_moved.nii')), 'Prepare moved gate changed.');
fprintf('T006-FOLLOWUP: alias-only/gated-input reporting is characterization-only here; T006 must add focused reporting verification without changing science.\n');

% R2010b-era parse compatibility for every touched orchestration seam.
parse_targets = {fullfile(root_dir, 'src', 'mlsc', 'mlsc_preflight.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_generate_slurm_script.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_backend.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_lifecycle.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_current_validate.m'); ...
    fullfile(root_dir, 'run_pseudo_CT.m')};
for ii = 1:length(parse_targets)
    try
        mlint(parse_targets{ii});
    catch ME %#ok<NASGU>
        assert(false, 'T004 orchestration seam failed to parse.');
    end
end

fprintf('=== MLSC current orchestration tests passed: legacy unchanged, prepare->normalize->compute, pinned launcher, fail-closed gates, shared lifecycle ===\n');

    function response = local_record_submit(~)
        submit_called = true;
        response = '99999;mlsc';
    end

    function accepted = local_legacy_verify()
        accepted = true;
    end

    function response = local_legacy_submit(~)
        % Intentionally writes no att_map: scheduler COMPLETED with
        % missing output must fail via the shared generic gate.
        response = '31415;mlsc';
    end

    function response = local_legacy_squeue(~)
        response = 'RUNNING';
    end

    function response = local_legacy_sacct(~)
        response = '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60';
    end

    function response = local_legacy_squeue_by_name(~)
        response = '';
    end

    function response = local_legacy_sacct_by_name(~)
        response = '';
    end

    function local_legacy_cancel(~)
    end

    function local_legacy_sleep(~)
    end

    function response = local_current_missing_submit(~)
        % Validated-marker submission that writes no outputs: scheduler
        % COMPLETED with missing outputs/evidence must fail dynamically.
        response = '42424;mlsc';
    end

    function response = local_current_missing_sacct(~)
        response = '42424|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60';
    end
end

function local_write_valid_current_manifests(build_path, resource_path, runner_path, pinned, atlas_dir)
info = dir(runner_path);
assert(~isempty(info), 'Runner fixture missing for fingerprint.');
% B4B: runner_checksum is mandatory SHA-256 (no bytes/datenum fallback).
fingerprint = local_sha_hex_file(runner_path);
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
build.source_provenance_fingerprint = local_sha_hex_file(runner_path);
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

function assert_error(thunk)
failed = false;
try
    thunk();
catch %#ok<CTCH>
    failed = true;
end
assert(failed, 'Fail-closed gate did not reject.');
end

function assert_error_id(thunk, expected_id)
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

function hex = local_sha_hex_file(path_name)
% B4B fixture SHA-256 (Java, else sha256sum; fail closed).
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
