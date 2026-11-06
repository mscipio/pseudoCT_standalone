function report = build_application(release, varargin)
%BUILD_APPLICATION Explicit-release preflight; compiles only when Mode is 'build'.
%   REPORT = BUILD_APPLICATION(RELEASE) with RELEASE explicit, for example
%   'R2010b', is a DRY RUN (default). It verifies that the executing MATLAB
%   release equals RELEASE, that the MATLAB Compiler is installed, that the
%   source revision is recorded, that the dependency roots and lock file are
%   present, that every mcc input exists, and it lists the application file
%   set. It never calls mcc and writes nothing.
%
%   Name-value options:
%     'Mode'              'dry-run' (default) or 'build'. Only 'build' compiles.
%     'OutputRoot'        Required for 'build'. The package is written to
%                         OUTPUTROOT/RELEASE. Existing packages are never
%                         overwritten. Must not be inside src/, external/ or
%                         compiled/.
%     'McrRoot'           MATLAB Runtime root recorded for the payload (build).
%     'SpmRoot', 'AtlasDir', 'AliasingRoot', 'DicomToNiftiRoot'
%                         Dependency roots (default: pinned external/ trees).
%     'LockSha256'        Optional expected SHA-256 of dependencies.lock.json.
%
%   Build mode requires a clean git tree and the MATLAB Runtime root.
%   Package layout mirrors an install root, so the bin/ launchers resolve
%   their siblings by relative path: bin/ (pseudoct, pseudoct-headless,
%   run_mlsc_current_payload.sh), src/ (interpreted runtime source),
%   app/ (run_pseudo_CT GUI/CLI build), payload/ (mlsc_current_payload),
%   resources/, application_manifest.txt and SHA256SUMS (see
%   verify_application_package). Compile support for any release is
%   UNVERIFIED until a real build is run; this file defines no support table.
%
%   Example: build_application('R2010b', 'OutputRoot', '<output-root>')
%   Example: build_application('R2010b', 'Mode', 'build', ...
%                'OutputRoot', '<output-root>', 'McrRoot', '<mcr-root>')

if nargin < 1
    error('pseudo_CT:BuildUsage', ...
        'An explicit release is required, for example build_application(''R2010b'').');
end
if ~ischar(release) || size(release, 1) ~= 1 || ...
        isempty(regexp(release, '^R[0-9]{4}[ab]$', 'once'))
    error('pseudo_CT:BuildUsage', 'Release must have the form R<year><a|b>, for example R2010b.');
end
if mod(numel(varargin), 2) ~= 0
    error('pseudo_CT:BuildUsage', 'Options must be name-value pairs.');
end
opt = struct('mode', 'dry-run', 'outputroot', '', 'mcrroot', '', 'locksha256', '', ...
    'spmroot', '', 'atlasdir', '', 'aliasingroot', '', 'dicom2niftiroot', '');
for ii = 1:2:numel(varargin)
    key = lower(varargin{ii});
    if ~ischar(key) || ~isfield(opt, key) || ~ischar(varargin{ii + 1})
        error('pseudo_CT:BuildUsage', 'Unknown or non-text build option.');
    end
    opt.(key) = varargin{ii + 1};
end
if ~any(strcmp(opt.mode, {'dry-run', 'build'}))
    error('pseudo_CT:BuildUsage', 'Mode must be dry-run or build.');
end

repo = local_canonical(fileparts(fileparts(mfilename('fullpath'))));
if isempty(opt.spmroot), opt.spmroot = fullfile(repo, 'external', 'spm8-r6313'); end
if isempty(opt.atlasdir), opt.atlasdir = fullfile(repo, 'external', 'Batch_atlas'); end
if isempty(opt.aliasingroot), opt.aliasingroot = fullfile(repo, 'external', 'correct_aliasing-0.4.0'); end
if isempty(opt.dicom2niftiroot), opt.dicom2niftiroot = fullfile(repo, 'external', 'dicom2nifti-1.2.5'); end

% Preflight. Every check fails before any compilation step.
report = struct('mode', opt.mode, 'release', release, 'mcc_invoked', false);
[report.matlab_release, report.matlab_version, report.compiler, report.arch] = ...
    local_check_matlab(release);
[report.source_commit, report.source_dirty] = local_source_state(repo);
report.lock_sha256 = local_check_lock(repo, opt.locksha256);
local_check_roots(opt);
plan = local_compile_plan(repo, opt, fullfile('<stage>'));
local_check_compile_inputs(plan.inputs);
report.compile_input_count = numel(plan.inputs);
fs = local_file_set(repo, opt.atlasdir);
report.entrypoints = fs.entrypoints;
report.source_file_count = numel(fs.src);
report.source_set_sha256 = local_text_sha256(fs.digest_text);
report.launcher_count = numel(fs.launchers);
report.resource_count = numel(fs.resources);
report.output_dir = '';
if ~isempty(opt.outputroot)
    report.output_dir = local_output_check(repo, opt.outputroot, release);
elseif strcmp(opt.mode, 'build')
    error('pseudo_CT:BuildUsage', 'Mode build requires an explicit OutputRoot.');
end
if strcmp(opt.mode, 'build')
    if report.source_dirty
        error('pseudo_CT:BuildDirtySource', ...
            'Build refuses a dirty source tree; commit or stash changes first (%s).', repo);
    end
    if isempty(opt.mcrroot) || exist(opt.mcrroot, 'dir') ~= 7 || ...
            exist(fullfile(opt.mcrroot, 'runtime', 'glnxa64'), 'dir') ~= 7
        error('pseudo_CT:BuildDependency', ...
            'Build requires McrRoot with runtime/glnxa64: %s', opt.mcrroot);
    end
    report = local_build(repo, release, report, opt, fs);
end
local_print_report(report);
end

function [matlab_release, matlab_version, compiler, arch] = local_check_matlab(release)
matlab_release = version('-release');
if ~strcmp(matlab_release, release(2:end))
    error('pseudo_CT:BuildReleaseMismatch', ...
        'Requested %s but the executing MATLAB is %s (%s); run the build from the matching MATLAB.', ...
        release, matlab_release, version);
end
matlab_version = version;
cinfo = ver('compiler');
if isempty(cinfo) || exist('mcc', 'file') == 0
    error('pseudo_CT:BuildCompilerMissing', ...
        'MATLAB Compiler (mcc) is not available for %s; cannot build.', release);
end
compiler = sprintf('%s %s', cinfo(1).Name, cinfo(1).Version);
arch = computer('arch');
end

function [head, dirty] = local_source_state(repo)
prev_dir = pwd;
cleanup_cd = onCleanup(@() cd(prev_dir));
cd(repo);
[s1, head_text] = system('git --no-pager rev-parse HEAD 2>&1');
[s2, status_text] = system('git -c color.ui=never --no-pager status --porcelain 2>&1');
token = regexp(head_text, '[0-9a-f]{40}', 'match', 'once');
if s1 ~= 0 || s2 ~= 0 || isempty(token)
    error('pseudo_CT:BuildSource', 'Source revision unavailable in %s (git rev-parse HEAD failed).', repo);
end
head = token;
dirty = ~isempty(strtrim(status_text));
end

function lock_sha = local_check_lock(repo, expected)
lock_path = fullfile(repo, 'dependencies.lock.json');
if exist(lock_path, 'file') ~= 2
    error('pseudo_CT:BuildDependency', 'Dependency lock missing: %s', lock_path);
end
lock_sha = local_sha256(lock_path);
if ~isempty(expected) && ~strcmpi(expected, lock_sha)
    error('pseudo_CT:BuildDependency', ...
        'dependencies.lock.json SHA-256 %s differs from expected %s.', lock_sha, expected);
end
% Required dependency entries must be present in the lock (tree digests are
% checked by tests/test_dependency_lock.py, not by this preflight).
code = ['import json,sys; d=json.load(open(sys.argv[1])); ' ...
    'ids=set(x["id"] for x in d["dependencies"]); ' ...
    'need=["correct_aliasing","dicom2nifti","spm8-r6313","batch-atlas-shared"]; ' ...
    'miss=[n for n in need if n not in ids]; ' ...
    'print("MISSING " + " ".join(miss) if miss else "DEPENDENCIES_PRESENT"); ' ...
    'sys.exit(1 if miss else 0)'];
[status, out] = system(sprintf('python3 -I -B -c ''%s'' ''%s'' 2>&1', code, lock_path));
if status ~= 0
    error('pseudo_CT:BuildDependency', 'Lock entries check failed: %s', strtrim(out));
end
end

function local_check_roots(opt)
local_require(fullfile(opt.spmroot, 'Contents.m'), 'SPM root (Contents.m)');
local_require(fullfile(opt.aliasingroot, 'config', 'defaults.m'), 'aliasing root (config/defaults.m)');
local_require(opt.dicom2niftiroot, 'dicom2nifti root');
local_require(opt.atlasdir, 'atlas directory');
names = local_atlas_names(opt.atlasdir);
for kk = 1:numel(names)
    local_require(fullfile(opt.atlasdir, names{kk}), 'atlas resource');
end
end

function plan = local_compile_plan(repo, opt, stage)
%LOCAL_COMPILE_PLAN Exact mcc argument lists. Preflight validates the inputs
%   listed here; the build passes the same lists unchanged to mcc.
spm = opt.spmroot;
cfggen = fullfile(stage, 'cfggen');
src_dirs = local_dirs(fullfile(repo, 'src'));
spm_dirs = {spm; fullfile(spm, 'matlabbatch'); fullfile(spm, 'config'); ...
    fullfile(spm, 'toolbox', 'Seg'); fullfile(spm, 'toolbox', 'DARTEL')};
plan.app_args = [{'-m', fullfile(repo, 'run_pseudo_CT.m'), '-d', fullfile(stage, 'app'), '-v'}, ...
    local_pairs('-I', [src_dirs; {spm; opt.aliasingroot; opt.dicom2niftiroot}])];
plan.payload_args = [{'-m', fullfile(repo, 'src', 'science', 'current', 'mlsc_current_payload.m'), ...
    '-d', fullfile(stage, 'payload'), '-R', '-nodisplay', '-v'}, ...
    local_pairs('-I', [src_dirs; spm_dirs; {opt.aliasingroot; opt.dicom2niftiroot; cfggen}]), ...
    local_pairs('-a', {cfggen; opt.aliasingroot; opt.dicom2niftiroot; ...
    fullfile(spm, 'config'); fullfile(spm, 'EEGtemplates'); ...
    fullfile(spm, 'toolbox', 'Seg'); fullfile(spm, 'toolbox', 'DARTEL'); ...
    fullfile(spm, 'spm_sample_vol.mexa64'); fullfile(spm, 'spm_bsplinc.mexa64'); ...
    fullfile(spm, 'spm_bsplins.mexa64'); fullfile(spm, 'spm_slice_vol.mexa64'); ...
    fullfile(spm, 'spm_conv_vol.mexa64'); fullfile(spm, 'toolbox', 'Seg', 'spm_mrf.mexa64'); ...
    fullfile(spm, 'toolbox', 'DARTEL', 'dartel2.mexa64'); ...
    fullfile(spm, 'toolbox', 'DARTEL', 'dartel3.mexa64'); ...
    fullfile(repo, 'src', 'qc', 'hot_map_mpitool_1024.mat'); fullfile(repo, 'CHANGELOG.md')})];
% Every entrypoint and -I/-a input, except the generated cfggen directory.
all_args = [plan.app_args, plan.payload_args];
inputs = {};
for kk = 2:numel(all_args)
    if any(strcmp(all_args{kk - 1}, {'-m', '-I', '-a'})) && ~strcmp(all_args{kk}, cfggen)
        inputs{end + 1, 1} = all_args{kk}; %#ok<AGROW>
    end
end
plan.inputs = unique(inputs);
end

function local_check_compile_inputs(inputs)
for kk = 1:numel(inputs)
    if exist(inputs{kk}, 'file') ~= 2 && exist(inputs{kk}, 'dir') ~= 7
        error('pseudo_CT:BuildCompileInputMissing', ...
            'mcc input missing before any compiler call: %s', inputs{kk});
    end
end
end

function local_require(path_text, label)
if exist(path_text, 'file') ~= 2 && exist(path_text, 'dir') ~= 7
    error('pseudo_CT:BuildDependency', 'Required %s missing: %s', label, path_text);
end
end

function names = local_atlas_names(atlas_dir)
fixed = {'ch2.nii'; 'new_segment_batch.mat'; 'dartel_existing_template_batch.mat'; ...
    'create_inverse_warped_batch.mat'; 'Template_1.nii'; 'Template_2.nii'; ...
    'Template_3.nii'; 'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'};
listed = dir(fullfile(atlas_dir, '*Atlas*.nii'));
if isempty(listed)
    error('pseudo_CT:BuildDependency', 'No *Atlas*.nii files in %s.', atlas_dir);
end
atlas = sort({listed.name})';
names = [fixed; atlas];
end

function fs = local_file_set(repo, atlas_dir)
fs.entrypoints = {'run_pseudo_CT.m'; 'src/science/current/mlsc_current_payload.m'};
fs.launchers = {'bin/pseudoct'; 'bin/pseudoct-headless'; 'scripts/run_mlsc_current_payload.sh'};
fs.src = local_walk(fullfile(repo, 'src'), 'src');
fs.resources = local_atlas_names(atlas_dir);
all_rels = sort([fs.entrypoints; fs.launchers; fs.src]);
digest_text = '';
for kk = 1:numel(all_rels)
    full_path = fullfile(repo, strrep(all_rels{kk}, '/', filesep));
    if exist(full_path, 'file') ~= 2
        error('pseudo_CT:BuildSource', 'Application file missing: %s', all_rels{kk});
    end
    digest_text = [digest_text sprintf('%s  %s\n', local_sha256(full_path), all_rels{kk})]; %#ok<AGROW>
end
fs.digest_text = digest_text;
end

function out_dir = local_output_check(repo, root_dir, release)
if exist(root_dir, 'file') == 2
    error('pseudo_CT:BuildOutputRejected', 'OutputRoot is a file: %s', root_dir);
end
canonical = local_canonical(root_dir);
if strcmp(canonical, repo)
    error('pseudo_CT:BuildOutputRejected', 'OutputRoot must not be the source root: %s', root_dir);
end
forbidden = {fullfile(repo, 'src'); fullfile(repo, 'external'); fullfile(repo, 'compiled')};
for kk = 1:numel(forbidden)
    base = local_canonical(forbidden{kk});
    if strcmp(canonical, base) || strncmp(canonical, [base filesep], length(base) + 1)
        error('pseudo_CT:BuildOutputRejected', ...
            'OutputRoot must be separate from source, dependencies and deployed artifacts: %s', root_dir);
    end
end
out_dir = fullfile(canonical, release);
if exist(out_dir, 'dir') == 7 || exist(out_dir, 'file') == 2 || ...
        exist([out_dir '.partial'], 'dir') == 7
    error('pseudo_CT:BuildOutputExists', 'A package already exists or is in progress: %s', out_dir);
end
end

function report = local_build(repo, release, report, opt, fs)
%LOCAL_BUILD The only branch that compiles. Reached only with Mode 'build'.
out_dir = report.output_dir;
stage = [out_dir '.partial'];
for dd = {'app', 'payload', 'resources', 'bin', 'cfggen'}
    local_mkdir(fullfile(stage, dd{1}));
end
cfggen = fullfile(stage, 'cfggen');
local_write_init_helpers(cfggen);
plan = local_compile_plan(repo, opt, stage);
local_compile(plan.app_args, fullfile(stage, 'mcc-app.log'));
local_compile(plan.payload_args, fullfile(stage, 'mcc-payload.log'));
local_require(fullfile(stage, 'app', 'run_pseudo_CT'), 'compiled application executable');
local_require(fullfile(stage, 'payload', 'mlsc_current_payload'), 'compiled payload executable');

% Interpreted runtime source at the same relative paths as an install root.
for kk = 1:numel(fs.src)
    dest = fullfile(stage, strrep(fs.src{kk}, '/', filesep));
    local_mkdir(fileparts(dest));
    copyfile(fullfile(repo, strrep(fs.src{kk}, '/', filesep)), dest, 'f');
end
for kk = 1:numel(fs.launchers)
    [~, base, ext] = fileparts(fs.launchers{kk});
    copyfile(fullfile(repo, strrep(fs.launchers{kk}, '/', filesep)), ...
        fullfile(stage, 'bin', [base ext]), 'f');
end
for kk = 1:numel(fs.launchers)
    [~, base, ext] = fileparts(fs.launchers{kk});
    launcher_path = fullfile(stage, 'bin', [base ext]);
    [status, out] = system(sprintf('chmod 755 "%s"', launcher_path));
    if status ~= 0
        error('pseudo_CT:BuildOutput', 'Cannot make launcher executable: %s', strtrim(out));
    end
end
% Launcher path contract: each bin/ script resolves its siblings from its own
% location (bin/..): bin/pseudoct -> bin/pseudoct-headless and src/cli,
% payload/ and application_manifest.txt for run_mlsc_current_payload.sh.
local_require(fullfile(stage, 'bin', 'pseudoct'), 'packaged CLI launcher');
local_require(fullfile(stage, 'bin', 'pseudoct-headless'), 'packaged headless launcher');
local_require(fullfile(stage, 'bin', 'run_mlsc_current_payload.sh'), 'packaged payload launcher');
local_require(fullfile(stage, 'src', 'cli', 'pseudoct_headless_cli_r2010b.m'), ...
    'packaged headless MATLAB bootstrap');

for kk = 1:numel(fs.resources)
    copyfile(fullfile(opt.atlasdir, fs.resources{kk}), ...
        fullfile(stage, 'resources', fs.resources{kk}), 'f');
end

% Manifest first (file_count includes the manifest), then the inventory.
rels = local_walk(stage, '');
stamp = local_stamp();
manifest_lines = {'schema pseudo-CT.application-package/v1'; ...
    ['release ' release]; ...
    ['matlab_version ' report.matlab_version]; ...
    ['matlab_release ' report.matlab_release]; ...
    ['compiler ' report.compiler]; ...
    ['arch ' report.arch]; ...
    ['source_commit ' report.source_commit]; ...
    'source_dirty 0'; ...
    ['source_set_sha256 ' report.source_set_sha256]; ...
    ['source_file_count ' num2str(report.source_file_count)]; ...
    ['lock_sha256 ' report.lock_sha256]; ...
    ['spm_root ' opt.spmroot]; ['atlas_dir ' opt.atlasdir]; ...
    ['aliasing_root ' opt.aliasingroot]; ['dicom2nifti_root ' opt.dicom2niftiroot]; ...
    ['mcr_root ' opt.mcrroot]; ...
    ['mcc_app ' local_mcc_text(plan.app_args)]; ['mcc_payload ' local_mcc_text(plan.payload_args)]; ...
    ['build_timestamp_utc ' stamp]; ...
    ['file_count ' num2str(numel(rels) + 1)]; ...
    'inventory_file SHA256SUMS'};
local_write_lines(fullfile(stage, 'application_manifest.txt'), manifest_lines);
all_rels = sort([rels; {'application_manifest.txt'}]);
inventory = cell(numel(all_rels), 1);
for kk = 1:numel(all_rels)
    inventory{kk} = sprintf('%s  %s', ...
        local_sha256(fullfile(stage, strrep(all_rels{kk}, '/', filesep))), all_rels{kk});
end
local_write_lines(fullfile(stage, 'SHA256SUMS'), inventory);
verify_application_package(stage);
if exist(out_dir, 'dir') == 7 || exist(out_dir, 'file') == 2
    error('pseudo_CT:BuildOutputExists', 'Package appeared during build; not overwriting: %s', out_dir);
end
[ok, msg] = movefile(stage, out_dir);
if ~ok
    error('pseudo_CT:BuildOutput', 'Cannot finalize package %s: %s', out_dir, msg);
end
report.mcc_invoked = true;
report.package_dir = out_dir;
end

function local_compile(mcc_args, log_path)
%LOCAL_COMPILE The single mcc call site. Only local_build reaches it.
diary(log_path);
diary on;
cleanup_diary = onCleanup(@() local_diary_off());
try
    mcc(mcc_args{:});
catch ME
    error('pseudo_CT:BuildMccFailed', 'mcc failed: %s (log %s)', ME.message, log_path);
end
end

function local_diary_off()
try
    diary off;
catch %#ok<CTCH>
end
end

function local_print_report(report)
fprintf('BUILD_APPLICATION mode=%s release=%s mcc_invoked=%d\n', ...
    report.mode, report.release, report.mcc_invoked);
fprintf('  matlab %s (%s) compiler %s arch %s\n', ...
    report.matlab_release, report.matlab_version, report.compiler, report.arch);
fprintf('  source_commit %s dirty=%d\n', report.source_commit, report.source_dirty);
fprintf('  lock_sha256 %s\n', report.lock_sha256);
fprintf('  compile_inputs %d present\n', report.compile_input_count);
fprintf('  file_set entrypoints=%d src=%d launchers=%d resources=%d source_set_sha256=%s\n', ...
    numel(report.entrypoints), report.source_file_count, report.launcher_count, ...
    report.resource_count, report.source_set_sha256);
if isempty(report.output_dir)
    fprintf('  output not specified (dry run writes nothing)\n');
else
    fprintf('  output %s\n', report.output_dir);
end
if strcmp(report.mode, 'dry-run')
    if report.source_dirty
        fprintf('  note: source tree is dirty; build mode would refuse it\n');
    end
    fprintf('PREFLIGHT_PASS (no mcc call)\n');
else
    fprintf('BUILD_PASS package=%s\n', report.package_dir);
end
end

function local_write_init_helpers(cfggen)
local_mkdir(cfggen);
local_write_lines(fullfile(cfggen, 'cfg_mlbatch_appcfg_1.m'), { ...
    'function [cfg, def] = cfg_mlbatch_appcfg_1'; ...
    '% Build-local deployed appcfg: mimics cfg_util(''dumpcfg'') output.'; ...
    'cfg = spm_cfg;'; 'def = [];'; 'end'});
local_write_lines(fullfile(cfggen, 'cfg_mlbatch_appcfg_master.m'), { ...
    'function cfg_mlbatch_appcfg_master'; ...
    '[cfg, def] = cfg_mlbatch_appcfg_1;'; ...
    'cfg_util(''addapp'', cfg, def);'; 'end'});
% Production listing: New Segment and DARTEL only.
local_write_lines(fullfile(cfggen, 'spm_cfg_static_tools.m'), { ...
    'function values = spm_cfg_static_tools'; ...
    'values = {tbx_cfg_preproc8 tbx_cfg_dartel};'; 'end'});
end

function local_mkdir(path_text)
if exist(path_text, 'dir') == 7
    return;
end
[ok, msg] = mkdir(path_text);
if ~ok
    error('pseudo_CT:BuildOutput', 'Cannot create %s: %s', path_text, msg);
end
end

function local_write_lines(path_text, lines)
fid = fopen(path_text, 'w');
if fid == -1
    error('pseudo_CT:BuildOutput', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid));
for kk = 1:numel(lines)
    fprintf(fid, '%s\n', lines{kk});
end
end

function out = local_pairs(name, list)
out = {};
for kk = 1:numel(list)
    out(end + 1:end + 2) = {name, list{kk}};
end
end

function text = local_mcc_text(args)
text = 'mcc';
for kk = 1:numel(args)
    text = [text ' ' args{kk}]; %#ok<AGROW>
end
end

function dirs = local_dirs(root_dir)
% Recursive source directories for -I; package (+), class (@) and private
% folders are resolved by MATLAB itself and are not put on the path.
dirs = {root_dir};
listed = dir(root_dir);
for kk = 1:numel(listed)
    name = listed(kk).name;
    if ~listed(kk).isdir || any(strcmp(name, {'.', '..'})) || any(name(1) == '+@') || ...
            strcmp(name, 'private')
        continue;
    end
    dirs = [dirs; local_dirs(fullfile(root_dir, name))]; %#ok<AGROW>
end
end

function rels = local_walk(root_dir, prefix)
% Every entry except '.' and '..', including dot-prefixed files and folders.
rels = {};
listed = dir(root_dir);
for kk = 1:numel(listed)
    name = listed(kk).name;
    if any(strcmp(name, {'.', '..'}))
        continue;
    end
    if isempty(prefix)
        rel = name;
    else
        rel = [prefix '/' name];
    end
    if listed(kk).isdir
        rels = [rels; local_walk(fullfile(root_dir, name), rel)]; %#ok<AGROW>
    else
        rels{end + 1, 1} = rel; %#ok<AGROW>
    end
end
end

function stamp = local_stamp()
[status, out] = system('date -u +%Y-%m-%dT%H:%M:%SZ');
stamp = 'unknown';
if status == 0
    stamp = strtrim(out);
end
end

function hex = local_sha256(path_text)
[status, out] = system(sprintf('sha256sum "%s"', path_text));
if status ~= 0
    error('pseudo_CT:BuildVerify', 'SHA-256 unavailable for %s: %s', path_text, strtrim(out));
end
hex = lower(regexp(out, '^[0-9a-fA-F]{64}', 'match', 'once'));
end

function hex = local_text_sha256(text)
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(uint8(text));
bytes = typecast(digest.digest(), 'uint8');
hex = lower(reshape(dec2hex(bytes, 2)', 1, []));
end

function p = local_canonical(path_text)
p = strtrim(path_text);
try
    p = char(java.io.File(p).getCanonicalPath());
catch %#ok<CTCH>
end
end
