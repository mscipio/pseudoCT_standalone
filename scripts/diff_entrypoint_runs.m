function diff_entrypoint_runs(local_dir, launchpad_dir, varargin)
% Investigation tool — investigation-cleanup-release.
%DIFF_ENTRYPOINT_RUNS Compare pseudo-CT intermediate outputs from two runs.
%   DIFF_ENTRYPOINT_RUNS(LOCAL_DIR, LAUNCHPAD_DIR) compares the file trees
%   in LOCAL_DIR and LAUNCHPAD_DIR, reporting per-file status as IDENTICAL,
%   DIVERGENT, EXPECTED_DIFF, LOCAL_ONLY, or LAUNCHPAD_ONLY.
%
%   DIFF_ENTRYPOINT_RUNS(..., 'Tolerance', VAL) sets the numeric tolerance
%   for NIfTI pixel comparisons (default: 1e-6).
%
%   DIFF_ENTRYPOINT_RUNS(..., 'OutputCSV', PATH) writes results to CSV at
%   PATH in addition to the console report.
%
%   DIFF_ENTRYPOINT_RUNS(..., 'Order', MODE) controls report ordering.
%   MODE can be 'timestamp' (default) or 'name'. Timestamp ordering uses
%   the local tree modification-time rank as the generation-order template.
%   Launchpad-only files are appended by their own modification-time rank.
%
%   The comparator does NOT change the working directory (cd-neutral).
%   Minimum supported MATLAB: R2010b.
%
%   Known expectations (built-in, no sidecar config needed):
%     Pseudo_CT_AC_Version.txt  — EXPECTED_DIFF (version string differs)
%     Fusion_MR_Pseudo_CT_validation.tiff — LOCAL_ONLY (QC image, local only)

tolerance = 1e-6;
output_csv = '';
order_mode = 'timestamp';

fix_args = 2;
if nargin > fix_args && rem(nargin - fix_args, 2) == 0
    for ii = 1:2:(nargin - fix_args)
        switch varargin{ii}
            case 'Tolerance'
                tolerance = varargin{ii + 1};
            case 'OutputCSV'
                output_csv = varargin{ii + 1};
            case 'Order'
                order_mode = varargin{ii + 1};
            otherwise
                fprintf(2, 'Unknown parameter: %s\n', varargin{ii});
        end
    end
elseif nargin > fix_args && rem(nargin - fix_args, 2) ~= 0
    fprintf(2, 'Name-value arguments must come in pairs.\n');
    return;
end

% ---- Known expectations ----
KNOWN_EXPECTED_DIFF = {'Pseudo_CT_AC_Version.txt'};  % different but expected
KNOWN_LOCAL_ONLY    = {'Fusion_MR_Pseudo_CT_validation.tiff'};  % only in local

% ---- Validate input dirs ----
if exist(local_dir, 'dir') ~= 7
    fprintf(2, 'ERROR: local_dir not found: %s\n', local_dir);
    return;
end
if exist(launchpad_dir, 'dir') ~= 7
    fprintf(2, 'ERROR: launchpad_dir not found: %s\n', launchpad_dir);
    return;
end

% ---- Gather file lists (flat, files only, skip . and ..) ----
local_files  = dir(fullfile(local_dir, '*'));
lp_files     = dir(fullfile(launchpad_dir, '*'));

local_file_list = local_files(~[local_files.isdir]);
lp_file_list    = lp_files(~[lp_files.isdir]);

local_names  = setdiff({local_file_list.name}, {'.', '..'});
lp_names     = setdiff({lp_file_list.name}, {'.', '..'});

all_names    = unique([local_names, lp_names]);
all_names    = sort(all_names);  % deterministic tie-breaker
local_ranks  = file_generation_ranks(local_file_list);
lp_ranks     = file_generation_ranks(lp_file_list);
all_names    = order_file_names(all_names, local_file_list, local_ranks, lp_file_list, lp_ranks, order_mode);

% ---- Result accumulator ----
num_files = length(all_names);
results = struct('filename', cell(num_files, 1), ...
                 'status',    cell(num_files, 1), ...
                 'detail',    cell(num_files, 1));
first_difference_idx = 0;

for f = 1:num_files
    fname = all_names{f};
    in_local = ismember(fname, local_names);
    in_lp    = ismember(fname, lp_names);

    results(f).filename = fname;

    % --- Only in one tree ---
    if ~in_local && in_lp
        results(f).status = 'LAUNCHPAD_ONLY';
        results(f).detail = '';
        continue;
    end
    if in_local && ~in_lp
        if ismember(fname, KNOWN_LOCAL_ONLY)
            results(f).status = 'LOCAL_ONLY';
            results(f).detail = 'known (QC artifact)';
        else
            results(f).status = 'LOCAL_ONLY';
            results(f).detail = '';
        end
        continue;
    end

    % --- Both trees have the file ---
    local_path  = fullfile(local_dir, fname);
    lp_path     = fullfile(launchpad_dir, fname);

    % --- Check known-expectations first ---
    if ismember(fname, KNOWN_EXPECTED_DIFF)
        results(f).status = 'EXPECTED_DIFF';
        results(f).detail = '';
        continue;
    end

    % --- Dispatch by extension with robust DICOM detection ---
    % Extension-based DICOM: known clinical/scanner extensions.
    % Magic-byte fallback catches extensionless, .IMA, .img, or
    % alternate-named DICOM files produced by Biograph mMR scanners.
    [~, ~, ext] = fileparts(fname);
    ext = lower(ext);
    known_dcm_exts = {'.dcm', '.ima', '.dicom', '.dic'};
    is_dcm = any(strcmp(ext, known_dcm_exts));
    if ~is_dcm
        is_dcm = is_dicom_file(local_path);
    end

    if strcmp(ext, '.nii')
        [status_str, detail_str] = compare_nifti(local_path, lp_path, tolerance);

    elseif is_dcm
        [status_str, detail_str] = compare_dicom(local_path, lp_path, tolerance);

    elseif strcmp(ext, '.mat')
        [status_str, detail_str] = compare_mat(local_path, lp_path);

    elseif any(strcmp(ext, {'.txt', '.log', '.sh', '.m'}))
        [status_str, detail_str] = compare_text(local_path, lp_path);

    else
        [status_str, detail_str] = compare_binary(local_path, lp_path);
    end

    results(f).status = status_str;
    results(f).detail = detail_str;

    % Track first unexpected difference in report order.  LOCAL_ONLY and
    % LAUNCHPAD_ONLY are often the earliest useful signal when the pipelines
    % generate different intermediate names (e.g., recentered *_moved files).
    if first_difference_idx == 0 && is_unexpected_difference(status_str, detail_str)
        first_difference_idx = f;
    end
end

% ---- Print report ----
fprintf('\n');
fprintf('=== Entrypoint Diff Report ===\n');
fprintf('Local:      %s\n', local_dir);
fprintf('Launchpad:  %s\n', launchpad_dir);
fprintf('Tolerance:  %g\n', tolerance);
fprintf('Order:      %s\n', order_mode);
fprintf('Files:      %d\n\n', num_files);

header_fmt = '%-50s %-20s %s\n';
fprintf(header_fmt, 'FILE', 'STATUS', 'DETAIL');
fprintf('%s\n', repmat('-', 1, 100));

counts = struct('IDENTICAL', 0, 'HEADER_ONLY_DIFF', 0, 'VOXEL_DIVERGENT', 0, ...
                'DIVERGENT', 0, 'EXPECTED_DIFF', 0, ...
                'LOCAL_ONLY', 0, 'LAUNCHPAD_ONLY', 0);

for f = 1:num_files
    fprintf(header_fmt, results(f).filename, results(f).status, results(f).detail);
    s = results(f).status;
    if isfield(counts, s)
        counts.(s) = counts.(s) + 1;
    end
end

% ---- Summary ----
fprintf('\n--- Summary ---\n');
fprintf('  IDENTICAL:         %d\n', counts.IDENTICAL);
fprintf('  HEADER_ONLY_DIFF:  %d\n', counts.HEADER_ONLY_DIFF);
fprintf('  VOXEL_DIVERGENT:   %d\n', counts.VOXEL_DIVERGENT);
fprintf('  DIVERGENT:         %d\n', counts.DIVERGENT);
fprintf('  EXPECTED_DIFF:     %d\n', counts.EXPECTED_DIFF);
fprintf('  LOCAL_ONLY:        %d\n', counts.LOCAL_ONLY);
fprintf('  LAUNCHPAD_ONLY:    %d\n', counts.LAUNCHPAD_ONLY);

if first_difference_idx > 0
    fprintf('\n*** First unexpected difference by %s order: %s ***\n', order_mode, results(first_difference_idx).filename);
    fprintf('    Status: %s\n', results(first_difference_idx).status);
    fprintf('    Detail: %s\n', results(first_difference_idx).detail);
else
    fprintf('\nNo unexpected differences detected.\n');
end

% ---- Optional CSV ----
if ~isempty(output_csv)
    write_csv(output_csv, results);
    fprintf('\nCSV written to: %s\n', output_csv);
end

return

% =====================================================================
function [status_str, detail_str] = compare_nifti(local_path, lp_path, tol)
%COMPARE_NIFTI Read NIfTI files and delegate to compare_nifti_data.
try
    hdr_local = spm_vol(local_path);
    hdr_lp    = spm_vol(lp_path);
    vol_local = spm_read_vols(hdr_local);
    vol_lp    = spm_read_vols(hdr_lp);
    [status_str, detail_str] = compare_nifti_data(hdr_local, hdr_lp, vol_local, vol_lp, tol);
catch ME
    status_str = 'DIVERGENT';
    detail_str = sprintf('NIfTI read error: %s', ME.message);
end
return

% =====================================================================
function [status_str, detail_str] = compare_dicom(local_path, lp_path, tol)
% Compare DICOM files: header metadata (dicominfo) AND pixel data (dicomread).
% Gracefully degrades to pixel-only or binary-only when toolboxes are absent,
% always reporting the degraded mode in the detail string.
header_checked = false;
try
    info_local = dicominfo(local_path);
    info_lp    = dicominfo(lp_path);
    header_checked = true;
    [header_ok, hdr_detail] = compare_dicom_header(info_local, info_lp);
    if ~header_ok
        status_str = 'DIVERGENT';
        detail_str = hdr_detail;
        return;
    end
catch
    % dicominfo not available — header comparison skipped
end

try
    img_local = dicomread(local_path);
    img_lp    = dicomread(lp_path);
    if ~isequal(size(img_local), size(img_lp))
        status_str = 'DIVERGENT';
        detail_str = sprintf('DICOM size mismatch: %s vs %s', ...
            mat2str(size(img_local)), mat2str(size(img_lp)));
        return;
    end
    max_diff = max(abs(double(img_local(:)) - double(img_lp(:))));
    if max_diff <= tol
        status_str = 'IDENTICAL';
        if header_checked
            detail_str = sprintf('DICOM pixel+header match, diff = %g', max_diff);
        else
            detail_str = sprintf('DICOM pixel match (header not checked), diff = %g', max_diff);
        end
    else
        status_str = 'DIVERGENT';
        if header_checked
            detail_str = sprintf('DICOM header match, pixel diff = %g', max_diff);
        else
            detail_str = sprintf('DICOM pixel diff = %g', max_diff);
        end
    end
catch
    % dicomread failed
    if ~header_checked
        % Neither dicominfo nor dicomread available — binary fallback
        [status_str, detail_str] = compare_binary(local_path, lp_path);
        detail_str = ['DICOM degraded to binary (no dicominfo/dicomread): ' detail_str];
        return;
    end
    % Header OK but pixel data unavailable — report what we know
    status_str = 'DIVERGENT';
    detail_str = 'DICOM header match but pixel data unavailable (dicomread failed)';
end
return

% ---------------------------------------------------------------------
function [ok, detail] = compare_dicom_header(info_local, info_lp)
% Compare key DICOM header fields that affect image interpretation.
% key_fields order matches a typical clinical DICOM header; fields
% absent from both sides are silently skipped.
key_fields = {'PatientName', 'PatientID', 'StudyInstanceUID', ...
              'SeriesInstanceUID', 'Rows', 'Columns', ...
              'PixelSpacing', 'SliceThickness', 'ImagePositionPatient', ...
              'ImageOrientationPatient', 'Modality', 'Manufacturer'};
detail = '';
n_mismatches = 0;
for k = 1:length(key_fields)
    fn = key_fields{k};
    in_local = isfield(info_local, fn);
    in_lp    = isfield(info_lp, fn);
    if in_local ~= in_lp
        n_mismatches = n_mismatches + 1;
        if n_mismatches > 1
            detail = [detail '; ']; %#ok<AGROW>
        end
        detail = [detail sprintf('%s: present in one only', fn)]; %#ok<AGROW>
    elseif in_local
        v_local = info_local.(fn);
        v_lp    = info_lp.(fn);
        if ~isequal(v_local, v_lp)
            n_mismatches = n_mismatches + 1;
            if n_mismatches > 1
                detail = [detail '; ']; %#ok<AGROW>
            end
            detail = [detail sprintf('%s: differ', fn)]; %#ok<AGROW>
        end
    end
end
if n_mismatches == 0
    ok = true;
else
    ok = false;
    detail = sprintf('DICOM header mismatch: %s', detail);
end
return

% =====================================================================
function [status_str, detail_str] = compare_mat(local_path, lp_path)
%COMPARE_MAT Compare .mat files: load+isequal, with top-level field-name diff.
try
    data_local = load(local_path);
    data_lp    = load(lp_path);
    if isequal(data_local, data_lp)
        status_str = 'IDENTICAL';
        detail_str = 'load+isequal match';
    else
        status_str = 'DIVERGENT';
        % Enumerate field-name differences at top level
        fn_local = fieldnames(data_local);
        fn_lp    = fieldnames(data_lp);
        only_local = setdiff(fn_local, fn_lp);
        only_lp    = setdiff(fn_lp, fn_local);
        common      = intersect(fn_local, fn_lp);

        diff_fields = {};
        for k = 1:length(common)
            if ~isequal(data_local.(common{k}), data_lp.(common{k}))
                diff_fields{end+1} = common{k}; %#ok<AGROW>
            end
        end

        parts = {};
        if ~isempty(only_local)
            parts{end+1} = ['local-only:' celljoin(only_local, ',')]; %#ok<AGROW>
        end
        if ~isempty(only_lp)
            parts{end+1} = ['lp-only:' celljoin(only_lp, ',')]; %#ok<AGROW>
        end
        if ~isempty(diff_fields)
            parts{end+1} = ['differ:' celljoin(diff_fields, ',')]; %#ok<AGROW>
        end

        if isempty(parts)
            detail_str = 'load+isequal mismatch (no fieldname diff)';
        else
            detail_str = ['load+isequal mismatch; ' ...
                          parts{1}];
            for j = 2:length(parts)
                detail_str = [detail_str '; ' parts{j}]; %#ok<AGROW>
            end
        end
    end
catch
    % load failed (function handles, etc.) — fall back to MD5
    [status_str, detail_str] = compare_md5(local_path, lp_path);
end
return

% =====================================================================
function [status_str, detail_str] = compare_text(local_path, lp_path)
[status_str, detail_str] = compare_md5(local_path, lp_path);
return

% =====================================================================
function [status_str, detail_str] = compare_md5(local_path, lp_path)
h_local = file_md5(local_path);
h_lp    = file_md5(lp_path);
% Delegate to compare_hash_strings for sentinel-safe comparison.
% Two READ_ERROR/MD5_UNAVAILABLE sentinels are NEVER reported as
% IDENTICAL — both sides failed and we cannot judge equivalence.
[status_str, detail_str] = compare_hash_strings(h_local, h_lp);
return

% =====================================================================
function [status_str, detail_str] = compare_binary(local_path, lp_path)
fid_local = fopen(local_path, 'r');
if fid_local == -1
    status_str = 'DIVERGENT';
    detail_str = sprintf('cannot open local: %s', local_path);
    return;
end
data_local = fread(fid_local, inf, '*uint8');
fclose(fid_local);

fid_lp = fopen(lp_path, 'r');
if fid_lp == -1
    status_str = 'DIVERGENT';
    detail_str = sprintf('cannot open launchpad: %s', lp_path);
    return;
end
data_lp = fread(fid_lp, inf, '*uint8');
fclose(fid_lp);

if isequal(data_local, data_lp)
    status_str = 'IDENTICAL';
    detail_str = sprintf('binary match (%d bytes)', numel(data_local));
else
    status_str = 'DIVERGENT';
    detail_str = sprintf('binary mismatch (%d vs %d bytes)', numel(data_local), numel(data_lp));
end
return

% =====================================================================
function h = file_md5(fpath)
% Compute MD5 hash of a file using Java MessageDigest (available in MATLAB).
try
    md = java.security.MessageDigest.getInstance('MD5');
    fid = fopen(fpath, 'r');
    if fid == -1
        h = 'READ_ERROR';
        return;
    end
    data = fread(fid, inf, '*uint8');
    fclose(fid);
    md.update(data);
    digest = md.digest();
    h = sprintf('%02x', typecast(digest, 'uint8'));
catch
    h = 'MD5_UNAVAILABLE';
end
return

% =====================================================================
function s = celljoin(c, delim)
%CELLJOIN Join cell array of strings with delimiter (R2010b-safe).
%   strjoin was introduced in R2013a — this avoids the dependency.
if isempty(c)
    s = '';
    return;
end
s = c{1};
for i = 2:length(c)
    s = [s delim c{i}]; %#ok<AGROW>
end
return

% =====================================================================
function ok = is_dicom_file(fpath)
%IS_DICOM_FILE Detect DICOM by magic bytes ("DICM" at offset 128).
%   Returns true if the file can be opened and the bytes at positions
%   129-132 (0-indexed 128-131) spell "DICM" in US-ASCII.
%   Works on extensionless / .IMA / alternate-named DICOM files
%   produced by clinical scanners.
ok = false;
fid = fopen(fpath, 'r');
if fid == -1, return; end
try
    fseek(fid, 128, 'bof');       % skip 128-byte DICOM preamble
    magic_bytes = fread(fid, 4, '*uint8')';
    ok = isequal(magic_bytes, uint8('DICM'));
catch  %#ok<CTCH>
    % fseek or fread failed — not a readable DICOM file
end
fclose(fid);
return

% =====================================================================
function ranks = file_generation_ranks(file_list)
%FILE_GENERATION_RANKS Rank files by modification time within one run tree.
%   The absolute timestamps between local and Launchpad runs are not expected
%   to match.  The rank within each tree is used as a proxy for generation
%   order, with filename order as the deterministic tie-breaker.
ranks = zeros(length(file_list), 1);
if isempty(file_list)
    return;
end
datenums = [file_list.datenum]';
names = {file_list.name}';
[~, name_order] = sort(names);
name_tiebreak = zeros(length(file_list), 1);
for ii = 1:length(name_order)
    name_tiebreak(name_order(ii)) = ii;
end
[~, order_idx] = sortrows([datenums, name_tiebreak]);
for ii = 1:length(order_idx)
    ranks(order_idx(ii)) = ii;
end
return

% =====================================================================
function ordered_names = order_file_names(all_names, local_file_list, local_ranks, lp_file_list, lp_ranks, order_mode)
%ORDER_FILE_NAMES Sort report rows by approximate generation order or name.
if strcmpi(order_mode, 'name')
    ordered_names = sort(all_names);
    return;
end
if ~strcmpi(order_mode, 'timestamp')
    fprintf(2, 'Unknown Order mode: %s. Falling back to timestamp.\n', order_mode);
end

order_keys = zeros(length(all_names), 1);
local_names = {local_file_list.name};
lp_names = {lp_file_list.name};
local_count = length(local_names);
for ii = 1:length(all_names)
    fname = all_names{ii};
    local_idx = find(strcmp(local_names, fname), 1);
    lp_idx = find(strcmp(lp_names, fname), 1);

    % Use LOCAL generation order as the template.  Launchpad copy-back can
    % rewrite mtimes, so its rank is only meaningful for files that have no
    % local counterpart.
    if ~isempty(local_idx)
        order_keys(ii) = local_ranks(local_idx);
    elseif ~isempty(lp_idx)
        order_keys(ii) = local_count + lp_ranks(lp_idx);
    else
        order_keys(ii) = ii;
    end
end

% all_names was pre-sorted by name, so the original index is a stable
% deterministic tie-breaker for same-rank files.
[~, order_idx] = sortrows([order_keys, (1:length(all_names))']);
ordered_names = all_names(order_idx);
return

% =====================================================================
function out = is_unexpected_difference(status_str, detail_str)
%IS_UNEXPECTED_DIFFERENCE True for differences worth surfacing as first hit.
out = false;
known_unexpected = {'DIVERGENT', 'LAUNCHPAD_ONLY', 'HEADER_ONLY_DIFF', 'VOXEL_DIVERGENT'};
if any(strcmp(status_str, known_unexpected))
    out = true;
elseif strcmp(status_str, 'LOCAL_ONLY')
    % Built-in expected local-only artifacts keep LOCAL_ONLY status but carry
    % an explanatory detail string.  Do not let those hide the first real
    % pipeline divergence.
    if isempty(strfind(detail_str, 'known'))
        out = true;
    end
end
return

% =====================================================================
function write_csv(path, results)
fid = fopen(path, 'w');
if fid == -1
    fprintf(2, 'Cannot open CSV file for writing: %s\n', path);
    return;
end
fprintf(fid, 'File,Status,Detail\n');
for f = 1:length(results)
    fprintf(fid, '%s,%s,%s\n', results(f).filename, results(f).status, results(f).detail);
end
fclose(fid);
return
