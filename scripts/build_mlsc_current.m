function build_mlsc_current(varargin)
%BUILD_MLSC_CURRENT Build compiled mlsc-current payload (T007, T014 authoritative).
%   BUILD_MLSC_CURRENT('OutputDir', DIR, 'SpmRoot', DIR, 'AtlasDir', DIR,
%   'AliasingRoot', DIR, 'McrRoot', DIR) verifies the EXECUTING approved
%   MATLAB via live introspection and compiles ONLY src/mlsc/
%   mlsc_current_payload.m via mcc. Any identity mismatch STOPS with error
%   (no fallback, no science change).
%
%   Approved build MATLAB (T014): /usr/pubsw/packages/matlab/26.1 R2026a
%   Update 2 26.1.0.3251617 glnxa64. Expected MCR_ROOT (launcher contract,
%   recorded not executed): /usr/pubsw/common/matlab/26.1. The launcher is
%   invoked as run_mlsc_current_payload.sh <MCR_ROOT> <phase>
%   <job_manifest> <resource_manifest> (MCR_ROOT first).
%
%   Ordering preserved: PREPARE (bundled alias/recenter) -> external
%   FreeSurfer mri_normalize (unchanged tcsh contract owned by
%   mlsc_generate_slurm_script) -> COMPUTE. This script never runs science;
%   it only compiles. No run_pseudo_CT compilation.
%
%   Output stays in ignored controlled NONPRODUCTION (default
%   dist/mlsc_current_build under the repo root). Rejects /usr/pubsw
%   outputs, compiled/mlsc-current/, tarballs. No commit/push/tag.
%
%   Generates immutable resource manifest (atlas/ch2/batch MATs/Templates/
%   TPM/hotmap + fingerprints; legacy defaults/runner/TPM not authority)
%   and machine-readable build manifest with the canonical validator
%   schema (runner full path as built, pinned mcr_root, release with R
%   prefix, update_minimum, mcr_version [26 1], arch, generation,
%   runner_checksum SHA-256, source_commit base HEAD plus content-bound
%   provenance fingerprint (canonical <relpath>\t<SHA256>\n per included
%   file sorted by path, SHA-256 over that text), canonical
%   required_outputs)
%   plus T007 build-environment provenance (full version/build/update,
%   Compiler, toolboxes, mcc options, entrypoint, dep/MEX inventory,
%   files/checksums, executable/resource fingerprints, thread policy).
%   Compilation is NOT Gate-A PASS; Gate-A evidence is finalized later
%   into a SEPARATE record file that binds (never rewrites) this
%   manifest.
%
%   Minimum supported MATLAB: R2010b (build host is R2026a per T014).

% Parse name-value args (R2010b-safe, no inputParser dependency).
out_dir_arg = '';
spm_arg = '';
atlas_arg = '';
alias_arg = '';
mcr_arg = '';
ii = 1;
while ii <= numel(varargin)
    if ~ischar(varargin{ii}) || size(varargin{ii}, 1) ~= 1
        error('pseudo_CT:BuildUsage', 'Build arguments must be name-value character rows.');
    end
    name_here = lower(strtrim(varargin{ii}));
    if ii + 1 > numel(varargin)
        error('pseudo_CT:BuildUsage', 'Missing value for build argument %s.', name_here);
    end
    val_here = varargin{ii + 1};
    if ~ischar(val_here) || size(val_here, 1) ~= 1
        error('pseudo_CT:BuildUsage', 'Build argument %s value must be a character row.', name_here);
    end
    switch name_here
        case 'outputdir'
            out_dir_arg = strtrim(val_here);
        case 'spmroot'
            spm_arg = strtrim(val_here);
        case 'atlasdir'
            atlas_arg = strtrim(val_here);
        case 'aliasingroot'
            alias_arg = strtrim(val_here);
        case 'mcrroot'
            mcr_arg = strtrim(val_here);
        otherwise
            error('pseudo_CT:BuildUsage', 'Unknown build argument %s.', name_here);
    end
    ii = ii + 2;
end

repo_root = fileparts(fileparts(mfilename('fullpath')));

% Defaults (T014 authoritative inputs; outputs stay under repo dist/).
dflt_spm = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
dflt_atlas = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/Batch_atlas';
dflt_alias = '/usr/pubsw/packages/mrpet/standalone_apps/correct_aliasing/correct_aliasing_standalone-0.3.0';
dflt_mcr = '/usr/pubsw/common/matlab/26.1';
dflt_out = fullfile(repo_root, 'dist', 'mlsc_current_build');
if isempty(spm_arg), spm_arg = dflt_spm; end
if isempty(atlas_arg), atlas_arg = dflt_atlas; end
if isempty(alias_arg), alias_arg = dflt_alias; end
if isempty(mcr_arg), mcr_arg = dflt_mcr; end
if isempty(out_dir_arg), out_dir_arg = dflt_out; end

% Output guard: never /usr/pubsw, never compiled/mlsc-current/, never tarball.
if ~isempty(strfind(out_dir_arg, '/usr/pubsw'))
    error('pseudo_CT:BuildOutputRejected', 'Output must not target /usr/pubsw: %s', out_dir_arg);
end
if ~isempty(strfind(out_dir_arg, 'compiled/mlsc-current'))
    error('pseudo_CT:BuildOutputRejected', 'Output must not target compiled/mlsc-current/: %s', out_dir_arg);
end
if length(out_dir_arg) >= 7 && strcmp(out_dir_arg(end-6:end), '.tar.gz')
    error('pseudo_CT:BuildOutputRejected', 'Output must not be a tarball: %s', out_dir_arg);
end
if length(out_dir_arg) >= 4 && strcmp(out_dir_arg(end-3:end), '.tgz')
    error('pseudo_CT:BuildOutputRejected', 'Output must not be a tarball: %s', out_dir_arg);
end

% 1. Verify EXECUTING MATLAB via live introspection (no path authority).
exp_release = '2026a';
exp_version = '26.1.0.3251617 (R2026a) Update 2';
exp_arch = 'glnxa64';
act_release = '';
act_version = '';
try
    act_release = version('-release');
catch ME
    error('pseudo_CT:BuildIdentityMismatch', 'Cannot introspect MATLAB release: %s', ME.message);
end
try
    act_version = version;
catch ME
    error('pseudo_CT:BuildIdentityMismatch', 'Cannot introspect MATLAB version: %s', ME.message);
end
if ~ischar(act_release) || ~strcmp(strtrim(act_release), exp_release)
    error('pseudo_CT:BuildIdentityMismatch', ...
        'MATLAB release mismatch (expected %s, actual %s); STOP, no fallback.', exp_release, act_release);
end
if ~ischar(act_version) || ~strcmp(strtrim(act_version), exp_version)
    error('pseudo_CT:BuildIdentityMismatch', ...
        'MATLAB version mismatch (expected %s, actual %s); STOP, no fallback.', exp_version, act_version);
end
act_mcr = [];
try
    act_mcr = mcrversion;
catch ME
    error('pseudo_CT:BuildIdentityMismatch', 'Cannot introspect mcrversion: %s', ME.message);
end
% R2026a reports scalar 26 here; accept scalar 26 or vector [26 1] only.
mcr_ok = false;
if isnumeric(act_mcr) && numel(act_mcr) == 1 && act_mcr(1) == 26
    mcr_ok = true;
elseif isnumeric(act_mcr) && numel(act_mcr) == 2 && act_mcr(1) == 26 && act_mcr(2) == 1
    mcr_ok = true;
end
if ~mcr_ok
    error('pseudo_CT:BuildIdentityMismatch', ...
        'MATLAB mcrversion mismatch (expected 26 or [26 1], actual %s); STOP, no fallback.', mat2str(act_mcr));
end
act_arch = '';
try
    act_arch = computer('arch');
catch ME
    error('pseudo_CT:BuildIdentityMismatch', 'Cannot introspect arch: %s', ME.message);
end
if ~ischar(act_arch) || ~strcmp(strtrim(act_arch), exp_arch)
    error('pseudo_CT:BuildIdentityMismatch', ...
        'MATLAB arch mismatch (expected %s, actual %s); STOP, no fallback.', exp_arch, act_arch);
end
try
    has_compiler = license('test', 'Compiler');
catch ME
    error('pseudo_CT:BuildIdentityMismatch', 'Cannot test Compiler license: %s', ME.message);
end
if ~(has_compiler == 1)
    error('pseudo_CT:BuildIdentityMismatch', 'MATLAB Compiler toolbox unavailable; STOP, no fallback.');
end
try
    has_image = license('test', 'Image_Toolbox');
    has_stats = license('test', 'Statistics_Toolbox');
catch ME
    error('pseudo_CT:BuildIdentityMismatch', 'Cannot test toolbox licenses: %s', ME.message);
end
if ~(has_image == 1)
    error('pseudo_CT:BuildIdentityMismatch', 'Image Processing Toolbox unavailable; STOP, no fallback.');
end
if ~(has_stats == 1)
    error('pseudo_CT:BuildIdentityMismatch', 'Statistics Toolbox unavailable; STOP, no fallback.');
end
act_root = matlabroot;
fprintf('BUILD_IDENTITY release=%s version=%s mcr=%s arch=%s root=%s\n', ...
    strtrim(act_release), strtrim(act_version), mat2str(act_mcr), strtrim(act_arch), act_root);

% 2. Provenance FIRST (deterministic; base HEAD + tracked mods + every
% untracked source + SHA-256, exclude .nfs). STOP before compile if impossible.
[git_head, git_status, tracked_mods, untracked_sources] = local_git_provenance(repo_root);
if isempty(git_head)
    error('pseudo_CT:BuildProvenance', 'Source provenance impossible (no HEAD); STOP before compile.');
end
fprintf('PROVENANCE head=%s tracked=%d untracked=%d\n', git_head, numel(tracked_mods), numel(untracked_sources));

% 3. Validate dependency roots BEFORE expensive work (fail-closed).
entrypoint = fullfile(repo_root, 'src', 'mlsc', 'mlsc_current_payload.m');
if exist(entrypoint, 'file') ~= 2
    error('pseudo_CT:BuildDependency', 'Entrypoint missing: %s', entrypoint);
end
% Entrypoint signature guard (phase, job_manifest, resource_manifest).
try
    entry_text = fileread(entrypoint);
catch ME
    error('pseudo_CT:BuildDependency', 'Cannot read entrypoint: %s', ME.message);
end
if isempty(strfind(entry_text, 'function mlsc_current_payload(phase, job_manifest_path, resource_manifest_path)'))
    error('pseudo_CT:BuildDependency', 'Entrypoint signature mismatch; STOP (no science change permitted).');
end
% Never compile run_pseudo_CT here.
if ~isempty(strfind(entrypoint, 'run_pseudo_CT'))
    error('pseudo_CT:BuildDependency', 'Build must compile ONLY mlsc_current_payload, not run_pseudo_CT.');
end
vers_dir = fullfile(repo_root, 'vers');
vers_files = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'};
for kk = 1:numel(vers_files)
    if exist(fullfile(vers_dir, vers_files{kk}), 'file') ~= 2
        error('pseudo_CT:BuildDependency', 'Required SPM override missing: %s', fullfile(vers_dir, vers_files{kk}));
    end
end
if exist(spm_arg, 'dir') ~= 7
    error('pseudo_CT:BuildDependency', 'SPM root missing: %s', spm_arg);
end
if exist(fullfile(spm_arg, 'matlabbatch', 'cfg_util.m'), 'file') ~= 2
    error('pseudo_CT:BuildDependency', 'SPM matlabbatch cfg_util missing under: %s', spm_arg);
end
if exist(fullfile(spm_arg, 'toolbox', 'Seg', 'TPM.nii'), 'file') ~= 2
    error('pseudo_CT:BuildDependency', 'SPM toolbox TPM missing: %s', fullfile(spm_arg, 'toolbox', 'Seg', 'TPM.nii'));
end
if exist(fullfile(spm_arg, 'toolbox', 'DARTEL', 'tbx_cfg_dartel.m'), 'file') ~= 2
    error('pseudo_CT:BuildDependency', 'DARTEL toolbox config missing under: %s', spm_arg);
end
if exist(fullfile(spm_arg, 'toolbox', 'Seg', 'tbx_cfg_preproc8.m'), 'file') ~= 2
    error('pseudo_CT:BuildDependency', 'Seg toolbox config missing under: %s', spm_arg);
end
required_mex = {'spm_sample_vol.mexa64'; 'spm_bsplinc.mexa64'; 'spm_bsplins.mexa64'; ...
    'spm_slice_vol.mexa64'; 'spm_conv_vol.mexa64'};
for kk = 1:numel(required_mex)
    if exist(fullfile(spm_arg, required_mex{kk}), 'file') ~= 2
        error('pseudo_CT:BuildDependency', 'Required MEX missing: %s', fullfile(spm_arg, required_mex{kk}));
    end
end
if exist(alias_arg, 'dir') ~= 7
    error('pseudo_CT:BuildDependency', 'Aliasing root missing: %s', alias_arg);
end
if exist(fullfile(alias_arg, 'correct_aliasing.m'), 'file') ~= 2
    error('pseudo_CT:BuildDependency', 'Aliasing facade missing: %s', fullfile(alias_arg, 'correct_aliasing.m'));
end
% Aliasing must be external standalone, never repo src or SPM.
canonical_alias = local_canonical(alias_arg);
canonical_src = local_canonical(fullfile(repo_root, 'src'));
canonical_spm = local_canonical(spm_arg);
if ~isempty(strfind(canonical_alias, canonical_src))
    error('pseudo_CT:BuildDependency', 'Aliasing root must be external standalone, never repo src.');
end
if ~isempty(strfind(canonical_alias, canonical_spm))
    error('pseudo_CT:BuildDependency', 'Aliasing root must be external standalone, never SPM.');
end
if exist(atlas_arg, 'dir') ~= 7
    error('pseudo_CT:BuildDependency', 'Atlas directory missing: %s', atlas_arg);
end
fixed_resources = {'ch2.nii'; 'new_segment_batch.mat'; 'dartel_existing_template_batch.mat'; ...
    'create_inverse_warped_batch.mat'; 'Template_1.nii'; 'Template_2.nii'; ...
    'Template_3.nii'; 'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'};
for kk = 1:numel(fixed_resources)
    if exist(fullfile(atlas_arg, fixed_resources{kk}), 'file') ~= 2
        error('pseudo_CT:BuildDependency', 'Atlas resource missing: %s', fullfile(atlas_arg, fixed_resources{kk}));
    end
end
hotmap_path = fullfile(repo_root, 'src', 'qc', 'hot_map_mpitool_1024.mat');
if exist(hotmap_path, 'file') ~= 2
    error('pseudo_CT:BuildDependency', 'QC colormap missing: %s', hotmap_path);
end
if exist(mcr_arg, 'dir') ~= 7
    error('pseudo_CT:BuildDependency', 'Expected MCR_ROOT missing: %s', mcr_arg);
end
% Payload forbids UI/Ganymed/creds/scheduler/selector/SSH/GUI on its path by
% construction; the build never adds those trees to -I/-a. If a future
% payload required them, STOP here rather than silently bundling.
forbidden_tokens = {'ganymed'; 'ssh2'; 'run_launchpad_cmd'; 'CreateIntWin'; 'openfig'};
for kk = 1:numel(forbidden_tokens)
    % Only the payload entrypoint header is scanned for accidental coupling;
    % full science files legitimately mention headless forbiddances in comments.
    if ~isempty(strfind(entry_text, ['addpath.*' forbidden_tokens{kk}]))
        error('pseudo_CT:BuildDependency', ...
            'Entrypoint must not depend on forbidden role %s; STOP.', forbidden_tokens{kk});
    end
end

% 4. Prepare output layout (ignored nonproduction only).
if exist(out_dir_arg, 'dir') ~= 7
    [ok_mk, msg_mk] = mkdir(out_dir_arg);
    if ~ok_mk
        error('pseudo_CT:BuildOutput', 'Cannot create output dir %s: %s', out_dir_arg, msg_mk);
    end
end
build_dir = fullfile(out_dir_arg, 'payload_build');
cfggen_dir = fullfile(out_dir_arg, 'cfggen');
if exist(cfggen_dir, 'dir') ~= 7
    [ok_cg, msg_cg] = mkdir(cfggen_dir);
    if ~ok_cg
        error('pseudo_CT:BuildOutput', 'Cannot create cfggen dir %s: %s', cfggen_dir, msg_cg);
    end
end

% 5. Build-local deployed SPM init helpers (durable, not temp probe).
% Official SPM recipe writes these into the source tree (forbidden); we
% generate build-local copies bundled via -I/-a with precedence so the
% deployed CTF initialises without modifying /usr/pubsw.
local_write_text(fullfile(cfggen_dir, 'cfg_mlbatch_appcfg_1.m'), { ...
    'function [cfg, def] = cfg_mlbatch_appcfg_1'; ...
    '% Build-local deployed appcfg (T007): mimics cfg_util(''dumpcfg'') output.'; ...
    '% Original: SPM config/cfg_mlbatch_appcfg.m -> cfg = spm_cfg; def = [].'; ...
    'cfg = spm_cfg;'; ...
    'def = [];'; ...
    'end'});
local_write_text(fullfile(cfggen_dir, 'cfg_mlbatch_appcfg_master.m'), { ...
    'function cfg_mlbatch_appcfg_master'; ...
    '% Build-local deployed master (T007): mimics cfg_util(''dumpcfg'') master.'; ...
    '[cfg, def] = cfg_mlbatch_appcfg_1;'; ...
    'cfg_util(''addapp'', cfg, def);'; ...
    'end'});
% Production toolbox listing: Seg (New Segment) + DARTEL only. Other SPM
% toolboxes (FieldMap/Shoot/Beamforming/...) are excluded by design; the
% payload runs exactly New Segment, DARTEL existing-template, and inverse
% warp (core defs) plus coreg/segment support.
local_write_text(fullfile(cfggen_dir, 'spm_cfg_static_tools.m'), { ...
    'function values = spm_cfg_static_tools'; ...
    '% Build-local static toolbox listing (T007 production): Seg + DARTEL only.'; ...
    'values = {tbx_cfg_preproc8 tbx_cfg_dartel};'; ...
    'end'});

% 6. Immutable resource manifest BEFORE expensive work (fail-closed).
resources_path = fullfile(out_dir_arg, 'mlsc_current_resources.mat');
resources = local_build_resources(atlas_arg, spm_arg, hotmap_path);
save(resources_path, 'resources');
% Human-readable fingerprint companion (same identities, not authority).
local_write_text(fullfile(out_dir_arg, 'mlsc_current_resources.txt'), ...
    local_resources_text(resources));

% 7. Canonical paths for mcc (avoid /usr vs /autofs dual-prefix shadowing).
c_entry = local_canonical(entrypoint);
c_vers = local_canonical(vers_dir);
c_spm = local_canonical(spm_arg);
c_spm_mb = local_canonical(fullfile(spm_arg, 'matlabbatch'));
c_spm_cfg = local_canonical(fullfile(spm_arg, 'config'));
c_spm_eeg = local_canonical(fullfile(spm_arg, 'EEGtemplates'));
c_spm_seg = local_canonical(fullfile(spm_arg, 'toolbox', 'Seg'));
c_spm_dartel = local_canonical(fullfile(spm_arg, 'toolbox', 'DARTEL'));
c_alias = local_canonical(alias_arg);
c_src = local_canonical(fullfile(repo_root, 'src'));
c_src_core = local_canonical(fullfile(repo_root, 'src', 'core'));
c_src_io = local_canonical(fullfile(repo_root, 'src', 'io'));
c_src_qc = local_canonical(fullfile(repo_root, 'src', 'qc'));
c_src_mlsc = local_canonical(fullfile(repo_root, 'src', 'mlsc'));
c_src_config = local_canonical(fullfile(repo_root, 'src', 'config'));
c_cfggen = local_canonical(cfggen_dir);
c_changelog = local_canonical(fullfile(repo_root, 'CHANGELOG.md'));

% mcc invocation: ONLY mlsc_current_payload (never run_pseudo_CT).
% -R -nodisplay only (no -singleCompThread, no OMP/MKL forcing per T001/T012).
mcc_args = {'-m', c_entry, '-d', local_canonical(build_dir), ...
    '-R', '-nodisplay', '-v', ...
    '-I', c_vers, '-I', c_cfggen, '-I', c_alias, ...
    '-I', c_spm_mb, '-I', c_spm, '-I', c_spm_cfg, ...
    '-I', c_spm_seg, '-I', c_spm_dartel, ...
    '-I', c_src, '-I', c_src_core, '-I', c_src_io, '-I', c_src_qc, ...
    '-I', c_src_mlsc, '-I', c_src_config, ...
    '-a', c_vers, '-a', c_cfggen, '-a', c_alias, ...
    '-a', c_spm_cfg, '-a', c_spm_eeg, ...
    '-a', c_spm_seg, '-a', c_spm_dartel, ...
    '-a', fullfile(c_spm, 'spm_sample_vol.mexa64'), ...
    '-a', fullfile(c_spm, 'spm_bsplinc.mexa64'), ...
    '-a', fullfile(c_spm, 'spm_bsplins.mexa64'), ...
    '-a', fullfile(c_spm, 'spm_slice_vol.mexa64'), ...
    '-a', fullfile(c_spm, 'spm_conv_vol.mexa64'), ...
    '-a', fullfile(c_spm_seg, 'spm_mrf.mexa64'), ...
    '-a', fullfile(c_spm_dartel, 'dartel2.mexa64'), ...
    '-a', fullfile(c_spm_dartel, 'dartel3.mexa64'), ...
    '-a', fullfile(c_src_qc, 'hot_map_mpitool_1024.mat'), ...
    '-a', c_changelog};
mcc_options_text = local_mcc_text(mcc_args);
fprintf('MCC_ARGS %s\n', mcc_options_text);

% Capture mcc log via diary (build evidence, preserved on failure).
mcc_log = fullfile(out_dir_arg, 'mcc_stdout.log');
if exist(mcc_log, 'file') == 2
    delete(mcc_log);
end
diary(mcc_log);
diary on;
mcc_ok = true;
mcc_err = '';
try
    mcc(mcc_args{:});
catch ME
    mcc_ok = false;
    mcc_err = sprintf('%s: %s', ME.identifier, ME.message);
    fprintf('MCC_FAILED %s\n', mcc_err);
end
try
    diary off;
catch %#ok<CTCH>
end
if ~mcc_ok
    error('pseudo_CT:BuildMccFailed', 'mcc failed: %s (log %s); STOP, log preserved.', mcc_err, mcc_log);
end

% 8. Structural verification only (no artifact execution).
runner_path = fullfile(build_dir, 'run_mlsc_current_payload.sh');
exe_path = fullfile(build_dir, 'mlsc_current_payload');
if exist(runner_path, 'file') ~= 2
    error('pseudo_CT:BuildVerify', 'Launcher missing: %s', runner_path);
end
if exist(exe_path, 'file') ~= 2
    error('pseudo_CT:BuildVerify', 'Executable stub missing: %s', exe_path);
end
% Launcher contract: MCR_ROOT first (T014).
try
    runner_text = fileread(runner_path);
catch ME
    error('pseudo_CT:BuildVerify', 'Cannot read launcher: %s', ME.message);
end
if isempty(strfind(runner_text, '<deployedMCRroot>')) && isempty(strfind(runner_text, 'MCRROOT="$1"'))
    error('pseudo_CT:BuildVerify', 'Launcher MCR_ROOT-first contract not found in %s.', runner_path);
end

% File inventory + checksums (SHA-256 via system, bytes via dir).
[build_files, build_checksums] = local_build_files(build_dir);
% Resource fingerprint: SHA-256 of the .mat resource manifest (bytes identity).
resource_fp = local_sha256(resources_path);
runner_fp = local_sha256(runner_path);
exe_fp = local_sha256(exe_path);

% No personal-path leak in machine-readable manifests (repo-relative only).
local_assert_no_personal_path(resources.atlas_dir, 'resources.atlas_dir');
for kk = 1:numel(build_files)
    local_assert_no_personal_path(build_files{kk}, 'build.files');
end

% 9. Machine-readable build manifest (authority; native pending Gate A).
% Canonical compatibility-identity fields EXACTLY match the validator
% contract (mlsc_current_validate local_validate_build): runner (full
% path as built; must equal config.current.runner textually, so the
% artifact is referenced in place), mcr_root (pinned), release (with R
% prefix, e.g. R2026a), update_minimum, mcr_version [major minor],
% arch, generation, runner_checksum (SHA-256 recomputed), source_commit
% (base HEAD), source_provenance_fingerprint (content-bound SHA-256 over
% canonical <relpath>\t<SHA256>\n per included file sorted by path),
% required_outputs (canonical 3). No dual
% synonymous sets: build-environment provenance stays under matlab_*
% (full version/build/update/root), never duplicated as second
% release/arch/version fields.
build_stamp = local_utc_stamp();
build = struct();
build.schema = 'pseudo-CT.mlsc-current-build/v1';
build.manifest_version = 1;
build.runner = runner_path;
build.mcr_root = mcr_arg;
if isempty(regexp(strtrim(act_release), '^[0-9]{4}[ab]$', 'once'))
    error('pseudo_CT:BuildIdentityMismatch', ...
        'MATLAB release has an unexpected shape: %s.', act_release);
end
build.release = ['R' strtrim(act_release)];
build.update_minimum = 2;
if isnumeric(act_mcr) && numel(act_mcr) == 1 && act_mcr(1) == 26
    build.mcr_version = [26 1];
elseif isnumeric(act_mcr) && numel(act_mcr) == 2 && act_mcr(1) == 26 && act_mcr(2) == 1
    build.mcr_version = [double(act_mcr(1)) double(act_mcr(2))];
else
    error('pseudo_CT:BuildIdentityMismatch', ...
        'MATLAB mcrversion cannot be normalized to [26 1]; STOP.');
end
build.arch = strtrim(act_arch);
build.generation = sprintf('%d.%d', build.mcr_version(1), build.mcr_version(2));
if ~local_is_valid_sha256(runner_fp)
    error('pseudo_CT:BuildVerify', ...
        'Runner SHA-256 unavailable; STOP (no size/existence fallback).');
end
build.runner_checksum = lower(strtrim(runner_fp));
build.source_commit = git_head;
build.source_provenance_fingerprint = local_provenance_fingerprint( ...
    repo_root, git_head, tracked_mods, untracked_sources);
build.required_outputs = {'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
build.source_tracked_mods = tracked_mods;
build.source_untracked = untracked_sources;
build.source_status = git_status;
build.build_timestamp_utc = build_stamp;
build.matlab_version = strtrim(act_version);
build.matlab_update = 'Update 2';
build.matlab_build = '26.1.0.3251617';
build.matlab_root = act_root;
build.compiler_identity = 'MATLAB Compiler 26.1 (R2026a)';
build.required_toolboxes = {'Image_Toolbox'; 'Statistics_Toolbox'; 'Compiler'};
build.mcc_options = mcc_options_text;
build.entrypoint = 'src/mlsc/mlsc_current_payload.m';
build.entrypoint_signature = 'mlsc_current_payload(phase, job_manifest_path, resource_manifest_path)';
build.spm_root = spm_arg;
build.spm_version = 'SPM8 r6313 (Contents.m Version 6313 23-Jan-2015)';
build.aliasing_root = alias_arg;
build.aliasing_version = '0.3.0';
build.atlas_dir = atlas_arg;
build.dep_inventory = {'vers/spm_vol_nifti.m'; 'vers/spm_preproc_write8.m'; ...
    'vers/spm_dicom_convert.m'; 'spm/cfg_util (matlabbatch precedence)'; ...
    'spm/spm_jobman'; 'toolbox/Seg/tbx_cfg_preproc8'; ...
    'toolbox/DARTEL/tbx_cfg_dartel'; 'correct_aliasing facade + transitives'; ...
    'src/core/pseudo_CT_current_prepare.m'; 'src/core/pseudo_CT_current_compute.m'; ...
    'src helpers move_image_2_MNI/head_mask_mprage/CT_2_att_map/reduce_bone_segment/quick_fusion_pseudo_ct/toverlay2/spm_reslice_david/pca-resolver/output/version-log'; ...
    'Image Processing (imfill/bwlabel/imdilate/imerode/imclose)'; 'Statistics (nlinfit)'};
build.mex_inventory = required_mex;
build.mex_extra_bundled = {'spm_mrf.mexa64'; 'dartel2.mexa64'; 'dartel3.mexa64'};
build.runner_contract = 'run_mlsc_current_payload.sh <MCR_ROOT> <phase> <job_manifest> <resource_manifest>';
build.resource_manifest_file = 'mlsc_current_resources.mat';
if ~local_is_valid_sha256(resource_fp) || ~local_is_valid_sha256(exe_fp)
    error('pseudo_CT:BuildVerify', ...
        'Resource/executable SHA-256 unavailable; STOP (no fallback).');
end
build.resource_fingerprint = lower(strtrim(resource_fp));
build.executable_fingerprint = lower(strtrim(exe_fp));
build.files = build_files;
build.checksums = build_checksums;
build.thread_policy = 'no -singleCompThread, no OMP/MKL=1 forcing; evidence-selected multithreading preferred';
build.compat_note = 'same release required; same update preferred, newer same-release update compatible; never different release or older update';
build.gate_a_status = 'pending: compilation is NOT Gate-A PASS; execution requires a separately finalized Gate-A record binding this manifest (see runbook)';
build.provenance_method = 'content-bound: canonical <relpath>\t<SHA256>\n per included file sorted by path, SHA-256 over that text; tracked mods + every untracked source, .nfs excluded; deterministic, no timestamps; fail closed on unreadable; base HEAD bound via source_commit + MATLAB introspection';
build_manifest_path = fullfile(out_dir_arg, 'mlsc_current_build.mat');
save(build_manifest_path, 'build');
local_write_text(fullfile(out_dir_arg, 'mlsc_current_build.txt'), local_build_text(build));
local_write_text(fullfile(out_dir_arg, 'mcc_args.txt'), {mcc_options_text});

fprintf('BUILD_SUCCESS out=%s runner=%s exe=%s\n', out_dir_arg, runner_path, exe_path);
fprintf('RESOURCES %s\n', resources_path);
fprintf('BUILD_MANIFEST %s\n', build_manifest_path);
end

function [head, status_text, tracked, untracked] = local_git_provenance(repo_root)
head = '';
status_text = '';
tracked = {};
untracked = {};
prev_dir = pwd;
cleanup_cd = onCleanup(@() cd(prev_dir)); %#ok<NASGU>
try
    cd(repo_root);
catch
    return;
end
try
    [s_head, head] = system('git --no-pager rev-parse HEAD 2>&1');
    head = local_clean_git_text(strtrim(head));
    % HEAD must be a 40-hex commit; anything else means capture failed.
    if s_head ~= 0 || numel(head) ~= 40
        head = '';
        return;
    end
    [~, status_raw] = system('git -c color.ui=false --no-pager status --porcelain=v1 2>&1');
    status_text = local_clean_git_text(strtrim(status_raw));
    [~, tracked_txt] = system('git --no-pager diff HEAD --name-only --no-color 2>&1');
    tracked = local_lines(strtrim(tracked_txt));
    [~, untracked_txt] = system('git ls-files --others --exclude-standard 2>&1');
    all_untracked = local_lines(strtrim(untracked_txt));
    untracked = {};
    for kk = 1:numel(all_untracked)
        if isempty(strfind(all_untracked{kk}, '.nfs'))
            untracked{end + 1, 1} = all_untracked{kk}; %#ok<AGROW>
        end
    end
    tracked = sort(tracked);
    untracked = sort(untracked);
catch
    head = '';
end
end

function lines = local_lines(txt)
lines = {};
if isempty(txt)
    return;
end
txt = local_clean_git_text(txt);
parts = strsplit(txt, char(10));
for kk = 1:numel(parts)
    t = strtrim(local_clean_git_text(parts{kk}));
    if ~isempty(t)
        lines{end + 1, 1} = t; %#ok<AGROW>
    end
end
end

function clean = local_clean_git_text(txt)
% Strip ANSI terminal escapes and carriage returns from git capture.
% system() under matlab -batch can wrap output with terminal init codes;
% unfiltered they pollute provenance paths with a ghost entry. R2010b-safe.
clean = '';
if ~ischar(txt) || isempty(txt)
    return;
end
esc = char(27);
cr = char(13);
kk = 1;
n = length(txt);
while kk <= n
    ch = txt(kk);
    if ch == esc
        % Skip CSI/escape sequence through its final byte (MATLAB-safe set).
        kk = kk + 1;
        if kk <= n && txt(kk) == '['
            kk = kk + 1;
            while kk <= n && ~((txt(kk) >= 'A' && txt(kk) <= 'Z') || ...
                    (txt(kk) >= 'a' && txt(kk) <= 'z') || txt(kk) == '~' || txt(kk) == '=')
                kk = kk + 1;
            end
            if kk <= n
                kk = kk + 1;
            end
        end
        continue;
    end
    if ch == cr
        kk = kk + 1;
        continue;
    end
    clean(end + 1) = ch; %#ok<AGROW>
    kk = kk + 1;
end
clean = strtrim(clean);
end

function p = local_canonical(path_text)
p = strtrim(path_text);
try
    jf = java.io.File(p);
    p = char(jf.getCanonicalPath());
catch %#ok<CTCH>
end
end

function fp = local_fingerprint(path_text)
info = dir(path_text);
if isempty(info)
    fp = 'missing';
    return;
end
fp = sprintf('bytes=%d;datenum=%.6f', info(1).bytes, info(1).datenum);
end

function resources = local_build_resources(atlas_dir, spm_dir, hotmap_path)
fixed = {'ch2.nii'; 'new_segment_batch.mat'; 'dartel_existing_template_batch.mat'; ...
    'create_inverse_warped_batch.mat'; 'Template_1.nii'; 'Template_2.nii'; ...
    'Template_3.nii'; 'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'};
listed = dir(fullfile(atlas_dir, '*Atlas*.nii'));
if isempty(listed)
    error('pseudo_CT:BuildDependency', 'No *Atlas*.nii in %s.', atlas_dir);
end
atlas_list = {};
for kk = 1:numel(listed)
    atlas_list{end + 1, 1} = listed(kk).name; %#ok<AGROW>
end
atlas_list = sort(atlas_list);
names = [fixed; atlas_list];
fps = {};
for kk = 1:numel(names)
    fp_here = local_fingerprint(fullfile(atlas_dir, names{kk}));
    if strcmp(fp_here, 'missing')
        error('pseudo_CT:BuildDependency', 'Atlas resource missing: %s', fullfile(atlas_dir, names{kk}));
    end
    fps{end + 1, 1} = fp_here; %#ok<AGROW>
end
tpm_fp = local_fingerprint(fullfile(spm_dir, 'toolbox', 'Seg', 'TPM.nii'));
qc_fp = local_fingerprint(hotmap_path);
if strcmp(tpm_fp, 'missing') || strcmp(qc_fp, 'missing')
    error('pseudo_CT:BuildDependency', 'TPM or QC fingerprint missing.');
end
native_names = {'spm_bsplinc.mexa64'; 'spm_bsplins.mexa64'; 'spm_conv_vol.mexa64'; ...
    'spm_sample_vol.mexa64'; 'spm_slice_vol.mexa64'};
native_names = sort(native_names);
native_fps = {};
for kk = 1:numel(native_names)
    fp_here = local_fingerprint(fullfile(spm_dir, native_names{kk}));
    if strcmp(fp_here, 'missing')
        error('pseudo_CT:BuildDependency', 'Native missing: %s', fullfile(spm_dir, native_names{kk}));
    end
    native_fps{end + 1, 1} = fp_here; %#ok<AGROW>
end
native_types = {'MEX'; 'MEX'; 'MEX'; 'MEX'; 'MEX'};
resources = struct();
resources.schema = 'pseudo-CT.mlsc-current-resources/v1';
resources.manifest_version = 1;
resources.atlas_dir = atlas_dir;
resources.atlas_list = atlas_list;
resources.resource_names = names;
resources.resource_fingerprints = fps;
resources.tpm_fingerprint = tpm_fp;
resources.qc_fingerprint = qc_fp;
resources.native_names = native_names;
resources.native_fingerprints = native_fps;
resources.native_types = native_types;
resources.native_platform = 'glnxa64';
resources.native_arch = 'glnxa64';
resources.native_validation = 't007-gate-a-pending: existence-only; production loadability evidence comes later';
end

function lines = local_resources_text(resources)
lines = {'# MLSC current resource manifest (human-readable companion; .mat is authority)'; ...
    sprintf('schema %s', resources.schema); ...
    sprintf('manifest_version %d', resources.manifest_version); ...
    sprintf('atlas_dir %s', resources.atlas_dir); ...
    sprintf('atlas_count %d', numel(resources.atlas_list)); ...
    sprintf('tpm_fingerprint %s', resources.tpm_fingerprint); ...
    sprintf('qc_fingerprint %s', resources.qc_fingerprint); ...
    sprintf('native_validation %s', resources.native_validation); ...
    '## resources (name fingerprint)'; ...
    };
for kk = 1:numel(resources.resource_names)
    lines{end + 1, 1} = sprintf('%s %s', resources.resource_names{kk}, resources.resource_fingerprints{kk}); %#ok<AGROW>
end
lines{end + 1, 1} = '## natives (name fingerprint type)'; %#ok<AGROW>
for kk = 1:numel(resources.native_names)
    lines{end + 1, 1} = sprintf('%s %s %s', resources.native_names{kk}, resources.native_fingerprints{kk}, resources.native_types{kk}); %#ok<AGROW>
end
end

function lines = local_build_text(build)
lines = {'# MLSC current build manifest (human-readable companion; .mat is authority)'; ...
    sprintf('schema %s', build.schema); ...
    sprintf('source_commit %s', build.source_commit); ...
    sprintf('source_provenance_fingerprint %s', build.source_provenance_fingerprint); ...
    sprintf('build_timestamp_utc %s', build.build_timestamp_utc); ...
    sprintf('release %s', build.release); ...
    sprintf('matlab_version %s', build.matlab_version); ...
    sprintf('mcr_version %s', mat2str(build.mcr_version)); ...
    sprintf('arch %s', build.arch); ...
    sprintf('generation %s', build.generation); ...
    sprintf('mcr_root %s', build.mcr_root); ...
    sprintf('runner %s', build.runner); ...
    sprintf('runner_contract %s', build.runner_contract); ...
    sprintf('runner_checksum %s', build.runner_checksum); ...
    sprintf('resource_fingerprint %s', build.resource_fingerprint); ...
    sprintf('gate_a_status %s', build.gate_a_status); ...
    };
end

function text = local_mcc_text(args)
text = '';
for kk = 1:numel(args)
    a = args{kk};
    if ~isempty(strfind(a, ' '))
        a = ['"' a '"']; %#ok<AGROW>
    end
    if kk == 1
        text = sprintf('mcc %s', a);
    else
        text = sprintf('%s %s', text, a);
    end
end
end

function [files, checksums] = local_build_files(build_dir)
listed = dir(fullfile(build_dir, '*'));
files = {};
checksums = {};
for kk = 1:numel(listed)
    if listed(kk).isdir
        continue;
    end
    files{end + 1, 1} = listed(kk).name; %#ok<AGROW>
    fp = local_sha256(fullfile(build_dir, listed(kk).name));
    checksums{end + 1, 1} = sprintf('%s bytes=%d sha256=%s', listed(kk).name, listed(kk).bytes, fp); %#ok<AGROW>
end
files = sort(files);
checksums = sort(checksums);
end

function h = local_sha256(path_text)
h = 'unavailable';
try
    [s, out] = system(sprintf('sha256sum "%s" 2>&1', path_text));
    if s == 0
        tok = strsplit(strtrim(out));
        if ~isempty(tok)
            h = tok{1};
        end
    end
catch %#ok<CTCH>
end
end

function flag = local_is_valid_sha256(value)
%LOCAL_IS_VALID_SHA256 Strict 64-hex SHA-256 shape (fail-closed build).
%   R2010b only.
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

function fp = local_provenance_fingerprint(repo_root, head, tracked, untracked)
%LOCAL_PROVENANCE_FINGERPRINT Content-bound deterministic fingerprint.
%   Canonical text is "<relpath>\t<SHA256>\n" per included file sorted by
%   path (tracked mods + every untracked source consumed, .nfs excluded),
%   SHA-256 over that text. Deterministic normalization (strtrimmed
%   relpaths sorted, lowercase hex, tab/newline separators), no timestamps.
%   Missing/unreadable/unhashable file STOPS the build (fail closed).
%   HEAD is validated (non-empty 40-hex) but bound separately via
%   source_commit; the fingerprint itself is content-only so same filenames
%   with changed contents yield different fingerprints. R2010b only.
if ~ischar(repo_root) || isempty(strtrim(repo_root)) || exist(strtrim(repo_root), 'dir') ~= 7
    error('pseudo_CT:BuildProvenance', ...
        'Source provenance root unavailable; STOP before compile.');
end
if ~ischar(head) || isempty(strtrim(head)) || numel(strtrim(head)) ~= 40
    error('pseudo_CT:BuildProvenance', ...
        'Source provenance HEAD invalid; STOP before compile.');
end
rels = {};
if iscell(tracked)
    for kk = 1:numel(tracked)
        if ischar(tracked{kk})
            t = strtrim(tracked{kk});
            if ~isempty(t) && isempty(strfind(t, '.nfs'))
                rels{end + 1, 1} = t; %#ok<AGROW>
            end
        end
    end
end
if iscell(untracked)
    for kk = 1:numel(untracked)
        if ischar(untracked{kk})
            t = strtrim(untracked{kk});
            if ~isempty(t) && isempty(strfind(t, '.nfs'))
                rels{end + 1, 1} = t; %#ok<AGROW>
            end
        end
    end
end
rels = sort(rels);
% Deduplicate deterministically (tracked/untracked are disjoint by git,
% but duplicates must not double-count).
uniq = {};
for kk = 1:numel(rels)
    if kk == 1 || ~strcmp(rels{kk}, rels{kk - 1})
        uniq{end + 1, 1} = rels{kk}; %#ok<AGROW>
    end
end
rels = uniq;
canonical = '';
for kk = 1:numel(rels)
    full_here = fullfile(strtrim(repo_root), rels{kk});
    h = local_sha256(full_here);
    if ~local_is_valid_sha256(h)
        error('pseudo_CT:BuildProvenance', ...
            'Source file unreadable or unhashable: %s; STOP before compile.', rels{kk});
    end
    canonical = [canonical rels{kk} char(9) lower(strtrim(h)) char(10)]; %#ok<AGROW>
end
try
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(uint8(canonical));
    bytes = typecast(digest.digest(), 'uint8');
    candidate = lower(reshape(dec2hex(bytes, 2)', 1, []));
    if local_is_valid_sha256(candidate)
        fp = candidate;
        return;
    end
catch %#ok<CTCH>
end
error('pseudo_CT:BuildProvenance', ...
    'Source provenance fingerprint unavailable; STOP before compile.');
end

function t = local_utc_stamp()
t = '';
try
    [~, out] = system('date -u +%Y-%m-%dT%H:%M:%SZ 2>&1');
    t = strtrim(out);
catch %#ok<CTCH>
end
if isempty(t)
    try
        t = [datestr(now, 'yyyy-mm-ddTHH:MM:SS') 'Z']; %#ok<DATST>
    catch %#ok<CTCH>
        t = 'unknown';
    end
end
end

function local_write_text(path_text, lines)
fid = fopen(path_text, 'w');
if fid == -1
    error('pseudo_CT:BuildOutput', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() local_close_fid(fid)); %#ok<NASGU>
for kk = 1:numel(lines)
    count = fprintf(fid, '%s\n', lines{kk});
    if count ~= length(lines{kk}) + 1
        error('pseudo_CT:BuildOutput', 'Incomplete write %s.', path_text);
    end
end
end

function local_close_fid(fid)
try
    fclose(fid);
catch %#ok<CTCH>
end
end

function local_assert_no_personal_path(value, label)
if ~ischar(value)
    return;
end
if ~isempty(strfind(value, '/home/')) || ~isempty(strfind(value, '/scratch/'))
    error('pseudo_CT:BuildVerify', 'Personal-path leak in %s: %s', label, value);
end
end
