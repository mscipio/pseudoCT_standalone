function status = restart_from_repos_checkpoint(experiment_root, launchpad_tmp, orig_mprage, batch_atlas, dry_run, sandbox_prefix, reuse_masked_checkpoint, use_compiled_spm8)
% Investigation tool — investigation-cleanup-release.
% RESTART_FROM_REPOS_CHECKPOINT  Controlled restart diagnostic from Launchpad
%   checkpoint files into the local SPM processing pipeline.
%
%   STATUS = RESTART_FROM_REPOS_CHECKPOINT(...) returns a struct with fields:
%     .ready          — true if preflight passed and the run is ready
%     .sandbox_tmp    — path to the sandbox MR_PET/tmp/ directory
%     .processing_dir — path to the processing work directory (proc/)
%     .dry_run        — whether this was a dry-run invocation
%     .blocked_reason — reason for blocked status (empty if ready)
%
%   RESTART_FROM_REPOS_CHECKPOINT(EXPERIMENT_ROOT) uses default paths for
%   the Launchpad checkpoint, original MPRAGE, and Batch_atlas, and runs
%   the full downstream pipeline (smoothing through att_map creation).
%
%   RESTART_FROM_REPOS_CHECKPOINT(EXPERIMENT_ROOT, LP_TMP, ORIG, BATCH, DRY)
%   allows overriding every input:
%     EXPERIMENT_ROOT  — base directory under which the sandbox is created
%                        (e.g., /autofs/.../pseudoCT_devel).
%     LP_TMP           — path to the Launchpad MR_PET/tmp directory
%                        containing the checkpoint files.
%     ORIG             — path to the original (non-normalized) MPRAGE
%                        file for att_map header geometry and subject mask.
%     BATCH            — path to Batch_atlas directory.
%     DRY_RUN          — if true (non-zero), stages files and reports what
%                        would run WITHOUT executing the SPM processing.
%
%   RESTART_FROM_REPOS_CHECKPOINT(..., SANDBOX_PREFIX) replaces the
%   timestamp-based sandbox name with a fixed prefix.  Intended for
%   deterministic testing only — do NOT use in production runs.
%     SANDBOX_PREFIX   — optional string; the sandbox is named
%                        restart_sandbox_<SANDBOX_PREFIX>[_rN].
%                        When empty/missing, timestamp-based naming is used.
%
%   RESTART_FROM_REPOS_CHECKPOINT(..., REUSE_MASKED_CHECKPOINT) when
%   true (non-zero), skips Step 1 smoothing/masking in
%   normalized_2_att_map and reuses the staged
%   smprage_normalized_repos.nii from the Launchpad checkpoint.
%   smprage_normalized_repos.nii becomes REQUIRED when enabled.
%   Default: false (run full smoothing pipeline).
%
%   RESTART_FROM_REPOS_CHECKPOINT(..., USE_COMPILED_SPM8) when
%   true (non-zero), executes Step 2 (New Segment) via the compiled
%   standalone spm8 executable from the Launchpad assets instead of
%   the local cfg_util.  This is a DIAGNOSTIC OPTION to test whether
%   the SPM execution path (compiled MCR 7.11 vs local MATLAB) is
%   the source of segmentation divergence.  Requires:
%     - Launchpad root (default or PSEUDOCT_LAUNCHPAD_ROOT env):
%       /autofs/.../standalone_apps/Pseudo_CT_launchpad
%     - MCR root (default or PSEUDOCT_MCR_ROOT env):
%       /usr/pubsw/common/matlab/7.11/
%   Default: false (use local cfg_util).
%   Typical usage: reuse_masked_checkpoint=1 + use_compiled_spm8=1
%   to isolate the SPM engine as the only variable.
%
%   Sandbox layout:
%     <experiment_root>/restart_sandbox_<timestamp>/MR_PET/tmp/
%       mprage.nii                    ← original MPRAGE (copied)
%       mprage_normalized_repos.nii   ← Launchpad checkpoint (copied)
%       proc/                         ← processing work_dir (all SPM outputs)
%         ... (all downstream outputs created here)
%
%   The script keeps the original test_data folders untouched.  Only the
%   sandbox is populated and written.
%
%   After completion, run:
%     diff_entrypoint_runs(<sandbox_tmp>, <launchpad_tmp>)
%   to compare outputs.
%
%   COMPATIBILITY: R2010b+.  No modern-only MATLAB APIs.
%
%   Examples:
%     % Minimal: uses default paths from repo root
%     restart_from_repos_checkpoint('/autofs/.../pseudoCT_devel');
%
%     % Dry run
%     restart_from_repos_checkpoint(pwd, lpTmp, orig, batch, 1);
%
%     % Full run with explicit paths
%     restart_from_repos_checkpoint('/data/exp', ...
%         '/data/test_data_launchpad/MR_PET/tmp', ...
%         '/data/test_data_launchpad/MR_PET/tmp/mprage.nii', ...
%         '/data/pseudoCT_standalone/dist/Batch_atlas', 0);
%
%     % Deterministic sandbox prefix (testing only)
%     restart_from_repos_checkpoint(pwd, lpTmp, orig, batch, 1, 'fixed_test');
%
%     % Reuse staged smoothing/masking checkpoint (skip spm_smooth)
%     restart_from_repos_checkpoint(pwd, lpTmp, orig, batch, 0, '', 1);
%
%     % Reuse checkpoint + compiled SPM8 for New Segment (isolate SPM engine)
%     restart_from_repos_checkpoint(pwd, lpTmp, orig, batch, 0, '', 1, 1);
%
%   See also normalized_2_att_map, diff_entrypoint_runs.

%% -----------------------------------------------------------------------
% Resolve arguments and defaults
%% -----------------------------------------------------------------------
if nargin < 1, error('At least 1 argument required (experiment_root). Type ''help restart_from_repos_checkpoint'' for usage.'); end
if nargin > 8, error('At most 8 arguments accepted.'); end

% Initialize status struct (populated as execution proceeds)
status = struct('ready', false, 'sandbox_tmp', '', 'processing_dir', '', ...
                'dry_run', false, 'blocked_reason', '');

repo_root = fileparts(mfilename('fullpath'));
repo_root = fileparts(repo_root);  % Scripts/ → repo root

% Setup MATLAB path FIRST — Batch_atlas resolution and validation
% functions live under src/config and must be on the path before use.
disp('Setting up MATLAB path ...');
addpath(fullfile(repo_root, 'src', 'config'), '-begin');
setup_pseudo_CT_paths(repo_root);
disp('  Path setup complete.');

% Default: Launchpad checkpoint directory
if nargin < 2 || isempty(launchpad_tmp)
    launchpad_tmp = '/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/test_data_launchpad/MR_PET/tmp';
end

% Default: original MPRAGE (for att_map header geometry)
if nargin < 3 || isempty(orig_mprage)
    orig_mprage = fullfile(launchpad_tmp, 'mprage.nii');
end

% Default: Batch_atlas directory
if nargin < 4 || isempty(batch_atlas)
    % Try the resolution function; if it fails, try dist/ fallback
    try
        batch_atlas = pseudo_CT_resolve_batch_atlas_path(repo_root);
    catch  %#ok<CTCH>
        batch_atlas = fullfile(repo_root, 'dist', 'Batch_atlas');
    end
end

if nargin < 5 || isempty(dry_run)
    dry_run = 0;
end
dry_run = logical(dry_run);
status.dry_run = dry_run;

% Optional deterministic sandbox prefix (testing only).  When set, the
% sandbox name uses this string instead of a timestamp-derived prefix.
if nargin < 6
    sandbox_prefix = '';
end

% Optional: reuse staged Launchpad smoothing/masking checkpoint instead
% of re-computing spm_smooth.  When true, smprage_normalized_repos.nii
% is REQUIRED in the Launchpad temp directory.
if nargin < 7 || isempty(reuse_masked_checkpoint)
    reuse_masked_checkpoint = false;
end
reuse_masked_checkpoint = logical(reuse_masked_checkpoint);

% Optional: use compiled SPM8 standalone for New Segment (diagnostic only).
% When true, Step 2 of normalized_2_att_map invokes the compiled spm8
% executable from the Launchpad assets instead of local cfg_util.
% Requires the Launchpad directory and MCR 7.11 to be accessible.
if nargin < 8 || isempty(use_compiled_spm8)
    use_compiled_spm8 = false;
end
use_compiled_spm8 = logical(use_compiled_spm8);

%% -----------------------------------------------------------------------
% Validate inputs
%% -----------------------------------------------------------------------
if ~exist(experiment_root, 'dir')
    error('Experiment root does not exist: %s', experiment_root);
end
if ~exist(launchpad_tmp, 'dir')
    error('Launchpad tmp directory not found: %s', launchpad_tmp);
end
if ~exist(orig_mprage, 'file')
    error('Original MPRAGE not found: %s', orig_mprage);
end
if ~exist(batch_atlas, 'dir')
    error('Batch_atlas directory not found: %s', batch_atlas);
end

% Verify key Launchpad checkpoint files
checkpoint_files = {'mprage_normalized_repos.nii'};
checkpoint_optional = {'smprage_normalized_repos.nii', 'mprage_normalized_repos_params.mat', ...
                       'mprage_normalized_repos_seg8.mat'};
for ii = 1:length(checkpoint_files)
    if ~exist(fullfile(launchpad_tmp, checkpoint_files{ii}), 'file')
        error('Required checkpoint file missing from Launchpad tmp: %s', checkpoint_files{ii});
    end
end

% When reuse_masked_checkpoint is enabled, smprage_normalized_repos.nii
% is REQUIRED (not optional) — the whole point is to reuse it.
if reuse_masked_checkpoint
    if ~exist(fullfile(launchpad_tmp, 'smprage_normalized_repos.nii'), 'file')
        error(['reuse_masked_checkpoint requires smprage_normalized_repos.nii ' ...
               'in Launchpad tmp: %s'], launchpad_tmp);
    end
end

%% -----------------------------------------------------------------------
% Disk-space preflight (fail-fast before staging)
%% -----------------------------------------------------------------------
% 500 MB minimum for SPM intermediates + outputs + staging copies.
% Uses Java File.getUsableSpace() when JVM is available (MATLAB default).
% If Java is unavailable, warns and proceeds.
min_bytes = 500 * 1024 * 1024;
free_bytes = check_disk_space_free_bytes(experiment_root, min_bytes);
if free_bytes >= 0
    disp(sprintf('  Disk space OK: %.0f MB free on %s', free_bytes / (1024*1024), experiment_root));
end

%% -----------------------------------------------------------------------
% Create sandbox (with collision retry)
%% -----------------------------------------------------------------------
max_retries = 5;
sandbox_created = false;
for attempt = 1:max_retries
    if isempty(sandbox_prefix)
        ts_num = now;
        ts_str = datestr(ts_num, 'dd-mmm-yyyy');
        % Sub-second fraction for collision resistance (R2010b-safe).
        % 86400 = seconds/day; the fractional day gives sub-second precision.
        ts_frac_sec = floor(86400 * (ts_num - floor(ts_num)));
        ts_frac_ms  = floor(mod(ts_num * 86400 * 1000, 1000));
        ts_rand = randi(999, 1);
        name_base = sprintf('%s_%05d%03d%03d', ...
                            ts_str, ts_frac_sec, ts_frac_ms, ts_rand);
    else
        name_base = sandbox_prefix;
    end
    if attempt == 1
        sandbox_name = sprintf('restart_sandbox_%s', name_base);
    else
        sandbox_name = sprintf('restart_sandbox_%s_r%d', name_base, attempt);
    end
    sandbox_root = fullfile(experiment_root, sandbox_name);
    sandbox_tmp  = fullfile(sandbox_root, 'MR_PET', 'tmp');

    % DETERMINISTIC collision guard: MATLAB's mkdir returns success even
    % when the directory already exists, so we must explicitly detect
    % pre-existing directories and retry before calling mkdir.
    if exist(sandbox_tmp, 'dir')
        if attempt < max_retries
            pause(0.05 * attempt);  % increasing backoff: 50, 100, 150, 200 ms
        end
        continue;
    end

    [ok_mk, msg_mk] = mkdir(sandbox_tmp);
    if ok_mk
        sandbox_created = true;
        break;
    end
    % mkdir failed for a reason other than pre-existence — retry with
    % a new suffix (e.g. transient file-system issue).
    if attempt < max_retries
        pause(0.05 * attempt);  % increasing backoff
    end
end
if ~sandbox_created
    error('Failed to create sandbox after %d attempts. Last error: %s', max_retries, msg_mk);
end

% Create processing subdirectory (work_dir must differ from input directory
% because normalized_2_att_map writes into its norm_mprage input in-place).
processing_dir = fullfile(sandbox_tmp, 'proc');
[ok_proc, msg_proc] = mkdir(processing_dir);
if ~ok_proc
    error('Failed to create processing directory: %s', msg_proc);
end

disp('========================================');
disp('RESTART_FROM_REPOS_CHECKPOINT');
disp(sprintf('  Experiment root: %s', experiment_root));
disp(sprintf('  Sandbox:         %s', sandbox_tmp));
disp(sprintf('  Launchpad tmp:   %s', launchpad_tmp));
disp(sprintf('  Orig MPRAGE:     %s', orig_mprage));
disp(sprintf('  Batch_atlas:     %s', batch_atlas));
disp(sprintf('  Dry run:         %d', dry_run));
disp(sprintf('  Reuse smprage:   %d', reuse_masked_checkpoint));
disp(sprintf('  Compiled SPM8:   %d', use_compiled_spm8));
disp('========================================');

%% -----------------------------------------------------------------------
% Stage checkpoint files into sandbox
%% -----------------------------------------------------------------------
disp('Staging checkpoint files ...');

% Required: normalized repositioned MPRAGE (the post-move_image_2_MNI image)
src_norm = fullfile(launchpad_tmp, 'mprage_normalized_repos.nii');
dst_norm = fullfile(sandbox_tmp, 'mprage_normalized_repos.nii');
[ok, msg] = copyfile(src_norm, dst_norm);
if ~ok
    error('Failed to copy normalized MPRAGE: %s', msg);
end
disp(sprintf('  Copied: mprage_normalized_repos.nii'));

% Required: original MPRAGE (for .mat header + subject mask volume)
% The ORIG_MPRAGE argument may point to the Launchpad tmp mprage.nii,
% or to a different location.  Copy it into the sandbox for consistency.
[~, orig_name, orig_ext] = fileparts(orig_mprage);
dst_orig = fullfile(sandbox_tmp, strcat(orig_name, orig_ext));
[ok, msg] = copyfile(orig_mprage, dst_orig);
if ~ok
    error('Failed to copy original MPRAGE: %s', msg);
end
disp(sprintf('  Copied: %s%s', orig_name, orig_ext));

% Optional: Launchpad smoothed file (for comparison only — not used in
% processing unless explicitly invoked as the normalized input)
for ii = 1:length(checkpoint_optional)
    src_opt = fullfile(launchpad_tmp, checkpoint_optional{ii});
    if exist(src_opt, 'file')
        dst_opt = fullfile(sandbox_tmp, checkpoint_optional{ii});
        [ok, msg] = copyfile(src_opt, dst_opt);
        if ok
            disp(sprintf('  Copied (optional): %s', checkpoint_optional{ii}));
        else
            disp(sprintf('  WARNING: could not copy optional file %s: %s', checkpoint_optional{ii}, msg));
        end
    end
end

norm_mprage_in_sandbox = dst_norm;
orig_mprage_in_sandbox = dst_orig;

disp(sprintf('  Sandbox ready at: %s', sandbox_tmp));

%% -----------------------------------------------------------------------
% Run or report
%% -----------------------------------------------------------------------
if dry_run
    disp('========================================');
    % Atlas role preflight BEFORE reporting readiness.  Uses substring
    % matching (mirrors normalized_2_att_map downstream: strfind on
    % resliced names).  Catches missing atlas roles early and handles
    % real filenames like Atlas_rCT_flipLR_repos_15subj.nii.
    atlas_list = dir(fullfile(batch_atlas, '*Atlas*.nii'));
    atlas_ready = true;
    if ~isempty(atlas_list)
        atlas_names = {atlas_list.name};
        has_rCT = false;
        has_mask = false;
        for ii = 1:length(atlas_names)
            if ~isempty(strfind(atlas_names{ii}, 'Atlas_rCT'))
                has_rCT = true;
            end
            if ~isempty(strfind(atlas_names{ii}, 'Atlas_head_mask'))
                has_mask = true;
            end
        end
        if ~has_rCT
            disp('  BLOCKED: No *Atlas*.nii file containing Atlas_rCT found in Batch_atlas.');
            atlas_ready = false;
        end
        if ~has_mask
            disp('  BLOCKED: No *Atlas*.nii file containing Atlas_head_mask found in Batch_atlas.');
            atlas_ready = false;
        end
        if atlas_ready
            disp('  Atlas role preflight: Atlas_rCT and Atlas_head_mask found.');
        end
    else
        disp('  BLOCKED: No *Atlas*.nii files found in Batch_atlas.');
        atlas_ready = false;
    end
    disp('DRY RUN — would execute:');
    disp(sprintf('  normalized_2_att_map(''%s'', ''%s'', ''%s'', ''%s'', %d, %d)', ...
        norm_mprage_in_sandbox, orig_mprage_in_sandbox, batch_atlas, processing_dir, reuse_masked_checkpoint, use_compiled_spm8));
    if ~atlas_ready
        disp('');
        disp('WARNING: Dry-run would fail due to missing atlas files above.');
        disp('Fix Batch_atlas and re-run dry_run before attempting full run.');
    end
    disp('========================================');
    disp('To run for real, call:');
    disp(sprintf('  restart_from_repos_checkpoint(''%s'', ''%s'', ''%s'', ''%s'', 0)', ...
        experiment_root, launchpad_tmp, orig_mprage, batch_atlas));
    disp('After completion, compare with:');
    disp(sprintf('  diff_entrypoint_runs(''%s'', ''%s'')', processing_dir, launchpad_tmp));
    disp('');
    disp('To clean up all sandboxes under the experiment root:');
    disp(sprintf('  rm -rf ''%s/restart_sandbox_*''', experiment_root));

    % Populate status for external callers (smoke tests, scripts)
    status.ready          = atlas_ready;
    status.sandbox_tmp    = sandbox_tmp;
    status.processing_dir = processing_dir;
    status.dry_run        = true;
    if ~atlas_ready
        status.blocked_reason = 'missing-atlas';
    end
else
    disp('========================================');
    disp('RUNNING downstream processing ...');
    disp(sprintf('  Normalized: %s', norm_mprage_in_sandbox));
    disp(sprintf('  Original:   %s', orig_mprage_in_sandbox));
    disp(sprintf('  Batch_atlas: %s', batch_atlas));
    disp(sprintf('  Work dir:    %s', processing_dir));
    disp('========================================');
    try
        Pf = normalized_2_att_map(norm_mprage_in_sandbox, orig_mprage_in_sandbox, batch_atlas, processing_dir, reuse_masked_checkpoint, use_compiled_spm8);
        disp('========================================');
        disp('PROCESSING COMPLETE.');
        disp(sprintf('  Output dir: %s', processing_dir));
        disp(sprintf('  %d output files created.', size(Pf, 1)));
        disp('');
        disp('To compare with Launchpad output:');
        disp(sprintf('  diff_entrypoint_runs(''%s'', ''%s'')', processing_dir, launchpad_tmp));
        disp('');
        disp('To clean up this sandbox:');
        disp(sprintf('  rm -rf ''%s''', sandbox_root));
        disp('========================================');

        % Populate status — full run succeeded
        status.ready          = true;
        status.sandbox_tmp    = sandbox_tmp;
        status.processing_dir = processing_dir;
        status.dry_run        = false;
    catch ME
        disp('========================================');
        disp(sprintf('PROCESSING FAILED: %s', ME.message));
        disp(sprintf('  Sandbox preserved at: %s', sandbox_tmp));
        disp(sprintf('  Processing dir:      %s', processing_dir));
        disp('  Inspect files above for partial results.');
        disp('');
        disp('To clean up this sandbox:');
        disp(sprintf('  rm -rf ''%s''', sandbox_root));
        disp('========================================');

        % Populate status — full run failed
        status.ready          = false;
        status.sandbox_tmp    = sandbox_tmp;
        status.processing_dir = processing_dir;
        status.dry_run        = false;
        status.blocked_reason = 'processing-error';

        rethrow(ME);
    end
end

return

%% =======================================================================
%  Helper: check available disk space (old-MATLAB-compatible)
%% =======================================================================
function free_bytes = check_disk_space_free_bytes(dir_path, min_bytes)
% CHECK_DISK_SPACE_FREE_BYTES  Fail-fast disk-space preflight.
%   FREE = CHECK_DISK_SPACE_FREE_BYTES(DIR_PATH, MIN_BYTES)
%   returns the number of free bytes on the filesystem containing DIR_PATH.
%   Errors if free space is below MIN_BYTES (operator-visible fail-fast).
%
%   Uses java.io.File.getUsableSpace() when the JVM is available (MATLAB
%   default).  When Java is unavailable (-nojvm, deployed mode), warns and
%   returns -1 without blocking — the operator accepts the risk.
%
%   COMPATIBILITY: R2010b+.  No modern-only APIs.

free_bytes = -1;  % sentinel: unavailable

try
    % Probe the path upward to find an existing ancestor for the Java call.
    probe = dir_path;
    while ~exist(probe, 'dir') && ~isempty(probe)
        probe = fileparts(probe);
    end
    if isempty(probe)
        probe = '/';
    end
    jfile = java.io.File(probe);
    free_bytes = jfile.getUsableSpace();
catch  %#ok<CTCH>
    % Java unavailable (-nojvm, deployed MATLAB, headless)
    disp('WARNING: Could not determine free disk space (Java/JVM unavailable).');
    disp('  Proceeding without disk-space preflight — operator accepts risk.');
    return;
end

if free_bytes >= 0 && free_bytes < min_bytes
    free_mb = free_bytes / (1024 * 1024);
    min_mb  = min_bytes  / (1024 * 1024);
    error('Insufficient disk space on %s: %.0f MB free (need at least %.0f MB).', ...
          probe, free_mb, min_mb);
end