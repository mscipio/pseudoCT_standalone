function [status_str, detail_str] = compare_nifti_data(hdr_local, hdr_lp, vol_local, vol_lp, tol)
% Investigation tool — investigation-cleanup-release.
%COMPARE_NIFTI_DATA Core NIfTI comparison — structured metrics, no file I/O.
%   [STATUS, DETAIL] = COMPARE_NIFTI_DATA(HDR_LOCAL, HDR_LP, VOL_LOCAL, VOL_LP, TOL)
%
%   HDR_LOCAL, HDR_LP: SPM-style header structs with .dim, .dt, .pinfo, .mat.
%   VOL_LOCAL, VOL_LP: 3D numeric volume arrays (must be same size).
%   TOL: numeric tolerance for header affine/pinfo and voxel comparisons.
%
%   STATUS: 'IDENTICAL' | 'HEADER_ONLY_DIFF' | 'VOXEL_DIVERGENT' | 'DIVERGENT'
%
%   Detail encodes compact structured metrics:
%     - Affine mat max diff, dim match/mismatch, dt match/mismatch, pinfo max diff
%     - Voxel max diff, voxel RMS diff
%     - Inside-head max/RMS and outside-head max/RMS (conservative mask)
%
%   Head mask heuristic: ref > 0.005 * max(abs(ref(:))) over finite voxels.
%   Conservative — derived purely from reference volume, no project-specific priors.
%
%   INDEPENDENTLY TESTABLE: No file I/O, no toolbox dependencies, no SPM path needed.
%   Minimum supported MATLAB: R2010b.

% ---- Size guard ----
if ~isequal(size(vol_local), size(vol_lp))
    status_str = 'DIVERGENT';
    detail_str = sprintf('size mismatch: %s vs %s', ...
        mat2str(size(vol_local)), mat2str(size(vol_lp)));
    return;
end

% ---- Header metrics ----
dim_ok = isequal(hdr_local.dim, hdr_lp.dim);
dt_ok  = isequal(hdr_local.dt, hdr_lp.dt);
mat_diff = max(abs(double(hdr_local.mat(:)) - double(hdr_lp.mat(:))));

pinfo_size_ok = isequal(size(hdr_local.pinfo), size(hdr_lp.pinfo));
if pinfo_size_ok
    pinfo_diff = max(abs(double(hdr_local.pinfo(:)) - double(hdr_lp.pinfo(:))));
else
    pinfo_diff = NaN;
end

header_ok = dim_ok && dt_ok && (mat_diff <= tol) && pinfo_size_ok && (pinfo_diff <= tol);

% ---- Voxel metrics ----
diff_vals = abs(double(vol_local(:)) - double(vol_lp(:)));
max_diff = max(diff_vals);
rms_diff = sqrt(mean(diff_vals.^2));

% ---- Masked (inside/outside head) metrics ----
[inMax, inRMS, outMax, outRMS] = compute_masked_diffs(vol_local, vol_lp, diff_vals);

% ---- Build compact header detail ----
if dim_ok
    dim_s = 'dim=ok';
else
    dim_s = sprintf('dim=%svs%s', mat2str(hdr_local.dim), mat2str(hdr_lp.dim));
end
if dt_ok
    dt_s = 'dt=ok';
else
    dt_s = sprintf('dt=%svs%s', mat2str(hdr_local.dt), mat2str(hdr_lp.dt));
end
mat_s = sprintf('mat=%.2g', mat_diff);
if pinfo_size_ok
    pinfo_s = sprintf('pinfo=%.2g', pinfo_diff);
else
    pinfo_s = sprintf('pinfoSize(%svs%s)', mat2str(size(hdr_local.pinfo)), mat2str(size(hdr_lp.pinfo)));
end
hdr_detail = [dim_s ' ' dt_s ' ' mat_s ' ' pinfo_s];

% ---- Build voxel detail ----
vox_detail = sprintf('max=%.2g rms=%.2g', max_diff, rms_diff);

% ---- Build mask detail (NaN-safe) ----
if isnan(inMax),  inMax_s = 'NA';  else inMax_s  = sprintf('%.2g', inMax);  end
if isnan(inRMS),  inRMS_s = 'NA';  else inRMS_s  = sprintf('%.2g', inRMS);  end
if isnan(outMax), outMax_s = 'NA'; else outMax_s = sprintf('%.2g', outMax); end
if isnan(outRMS), outRMS_s = 'NA'; else outRMS_s = sprintf('%.2g', outRMS); end
mask_detail = sprintf('in:max=%s rms=%s out:max=%s rms=%s', inMax_s, inRMS_s, outMax_s, outRMS_s);

% ---- Status dispatch ----
if header_ok && max_diff <= tol
    status_str = 'IDENTICAL';
    detail_str = sprintf('NIfTI match | %s | vox:%s', hdr_detail, vox_detail);
elseif ~header_ok && max_diff <= tol
    status_str = 'HEADER_ONLY_DIFF';
    detail_str = sprintf('hdr: %s | vox:%s', hdr_detail, vox_detail);
elseif header_ok && max_diff > tol
    status_str = 'VOXEL_DIVERGENT';
    detail_str = sprintf('hdr=ok | vox:%s | %s', vox_detail, mask_detail);
else
    status_str = 'DIVERGENT';
    detail_str = sprintf('hdr: %s | vox:%s | %s', hdr_detail, vox_detail, mask_detail);
end
return

% =====================================================================
function [inMax, inRMS, outMax, outRMS] = compute_masked_diffs(vol_ref, vol_other, diff_vals)
%COMPUTE_MASKED_DIFFS Inside/outside-head difference metrics.
%   Head mask: ref > 0.005 * max(abs(ref)) AND both sides finite.
%   Conservative heuristic — no project-specific priors, no atlases.
%   Returns NaN for regions with zero voxels in that mask.

ref_v = double(vol_ref(:));
oth_v = double(vol_other(:));
dv    = double(diff_vals(:));

ref_max = max(abs(ref_v));
if ref_max == 0 || ~isfinite(ref_max)
    mask = true(size(ref_v));
else
    mask = ref_v > 0.005 * ref_max;
end
mask = mask(:) & isfinite(ref_v) & isfinite(oth_v);

if any(mask)
    inMax = max(dv(mask));
    inRMS = sqrt(mean(dv(mask).^2));
else
    inMax = NaN;
    inRMS = NaN;
end
if any(~mask)
    outMax = max(dv(~mask));
    outRMS = sqrt(mean(dv(~mask).^2));
else
    outMax = NaN;
    outRMS = NaN;
end
return
