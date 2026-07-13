function sweep_smoothing_fwhm(input_nii, ref_smprage, fwhm_min, fwhm_max, fwhm_step, out_dir)
% Investigation tool — investigation-cleanup-release.
%SWEEP_SMOOTHING_FWHM Sweep spm_smooth FWHM to find best match vs reference.
%   SWEEP_SMOOTHING_FWHM(INPUT_NII, REF_SMPRAGE, FWHM_MIN, FWHM_MAX, FWHM_STEP, OUT_DIR)
%   runs spm_smooth(INPUT_NII, OUTPUT, FWHM) at each step value and compares
%   the result to REF_SMPRAGE. Reports max pixel diff and RMS error for
%   each FWHM, plus the best match.
%
%   All outputs are written to OUT_DIR (default: tempname).
%
%   Example:
%     sweep_smoothing_fwhm(...
%       '/path/to/mprage_normalized_repos.nii', ...
%       '/path/to/smprage_normalized_repos.nii', ...
%       0, 4, 0.25);

if nargin < 3, fwhm_min  = 0;   end
if nargin < 4, fwhm_max  = 4;   end
if nargin < 5, fwhm_step = 0.1; end
if nargin < 6, out_dir   = tempname; end

if ~exist(out_dir, 'dir'), mkdir(out_dir); end

fprintf('Sweeping spm_smooth FWHM from %.2f to %.2f (step %.2f)\n', ...
    fwhm_min, fwhm_max, fwhm_step);
fprintf('Input:  %s\n', input_nii);
fprintf('Ref:    %s\n', ref_smprage);
fprintf('Out:    %s\n\n', out_dir);

fwhm_vals = fwhm_min:fwhm_step:fwhm_max;
n = length(fwhm_vals);

ref_vol = spm_read_vols(spm_vol(ref_smprage));
ref_vol = double(ref_vol);
ref_vol(isnan(ref_vol)) = 0;

results = zeros(n, 3); % [fwhm, max_diff, rms]

best_fwhm   = NaN;
best_max    = Inf;
best_rms    = Inf;

fprintf('%-10s  %-16s  %-16s\n', 'FWHM', 'max_pixel_diff', 'rms_error');
fprintf('%s\n', repmat('-', 50, 1));

for i = 1:n
    fw = fwhm_vals(i);
    out_fn = fullfile(out_dir, sprintf('smprage_fwhm_%.2f.nii', fw));

    % Run spm_smooth
    spm_smooth(input_nii, out_fn, fw);

    % Read result
    vol = spm_read_vols(spm_vol(out_fn));
    vol = double(vol);
    vol(isnan(vol)) = 0;

    % Compare to reference
    if ~isequal(size(vol), size(ref_vol))
        fprintf('%-10.2f  SIZE MISMATCH (local %s vs ref %s)\n', ...
            fw, mat2str(size(vol)), mat2str(size(ref_vol)));
        results(i, :) = [fw, NaN, NaN];
        continue;
    end

    diff_vol = abs(vol - ref_vol);
    max_d  = max(diff_vol(:));
    rms_d  = sqrt(mean(diff_vol(:).^2));

    results(i, :) = [fw, max_d, rms_d];

    fprintf('%-10.2f  %-16.6g  %-16.6g', fw, max_d, rms_d);
    if max_d < best_max
        best_max  = max_d;
        best_rms  = rms_d;
        best_fwhm = fw;
        fprintf('  <-- BEST');
    end
    fprintf('\n');
end

fprintf('\n=== BEST MATCH: FWHM = %.2f (max diff = %g, RMS = %g) ===\n', ...
    best_fwhm, best_max, best_rms);

% Save results table
csv_fn = fullfile(out_dir, 'fwhm_sweep_results.csv');
fid = fopen(csv_fn, 'w');
fprintf(fid, 'FWHM,max_diff,rms\n');
for i = 1:n
    fprintf(fid, '%.2f,%g,%g\n', results(i,1), results(i,2), results(i,3));
end
fclose(fid);
fprintf('\nResults saved: %s\n', csv_fn);
fprintf('Output dir:    %s\n', out_dir);

end
