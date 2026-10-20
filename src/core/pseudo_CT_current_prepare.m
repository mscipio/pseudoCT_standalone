function [P_out, handoff, early_return, fh] = pseudo_CT_current_prepare(P_in, dir_batch_templates_in, check_aliasing_in, config, output_context_in, recenter_override_in)
%PSEUDO_CT_CURRENT_PREPARE Pre-normalization preparation for current pipeline.
%   Shared by atlas_based_attenuation_map (local-current facade) and
%   mlsc_current_payload (compiled-current prepare phase). Implements the
%   pre-normalization order exactly: optional reslice, normalized/moved
%   suffix gates, correct_aliasing(input,output,'AliasCorrection',bool,
%   'Centering',bool,'Overwrite',true), R2019+ gate, success/partial/
%   early-return semantics.
%
%   Headless is explicitly opt-in and default-off: headless is true only
%   when config.headless or output_context.headless explicitly opts in.
%   Existing callers without either field observe unchanged behavior.
%   On the headless path this helper performs bundled SPM initialization,
%   skips Ganymed javaaddpath and forbids CreateIntWin/openfig figure
%   creation (fh = []).
%
%   Inputs mirror the facade contract:
%     P_in: char matrix of selected input images (facade passes P).
%     dir_batch_templates_in: atlas/batch template directory ('' selects
%       config.atlas_root).
%     check_aliasing_in: scalar 0/1 aliasing request.
%     config: selected profile config struct.
%     output_context_in: logging context struct (optional, default struct()).
%     recenter_override_in: optional override (optional, default [] meaning
%       use config.recenter_before_normalization).
%
%   Outputs:
%     P_out: prepared P char matrix (valid unless early_return).
%     handoff: scalar struct with schema
%       'pseudo-CT.current-handoff/v1', fields input_selected,
%       needs_normalization, normalized_expected, aliasing_effective,
%       recenter_effective, atlas_dir, code_version, headless.
%     early_return: logical true when the caller must return Pf = ''
%       (missing atlases, or aliasing/recenter failure path).
%     fh: interactive figure handle for the non-headless path, [] when
%       headless or when creation failed.
%
%   Minimum supported MATLAB: R2010b.

P_out = P_in;
handoff = struct();
early_return = false;
fh = [];

if nargin < 4 || ~isstruct(config) || numel(config) ~= 1
    error('pseudo_CT:ProfileRequired', ...
        'pseudo_CT_current_prepare requires the selected profile config.');
end
if nargin < 5 || isempty(output_context_in) || ~isstruct(output_context_in)
    output_context_in = struct();
end
output_context = output_context_in;
if nargin < 6
    recenter_override_in = [];
end
recenter_override = recenter_override_in;
P = P_in;
dir_batch_templates = dir_batch_templates_in;
check_aliasing = check_aliasing_in;
if ~ischar(dir_batch_templates_in) || size(dir_batch_templates_in, 1) ~= 1
    % Preserve facade semantics: empty selects config.atlas_root; other
    % types flow through to dir() and fail there as before.
    if isempty(dir_batch_templates_in)
        dir_batch_templates = '';
    end
end

headless = local_headless_enabled(config, output_context);
if headless
    local_ensure_spm_headless();
end

code_version = local_resolve_code_version();

autom_select_folder = isempty(dir_batch_templates);
if autom_select_folder
    dir_batch_templates = config.atlas_root;
end

if ~headless
    if isdir(fullfile(dir_batch_templates, 'ganymed-ssh2-build250'))
        a = javaclasspath;
        if (length(a) == 0) || (length(strfind(a{1}, 'ganymed-ssh2-build250')) == 0)
            javaaddpath(fullfile(dir_batch_templates, 'ganymed-ssh2-build250', 'ganymed-ssh2-build250.jar'));
        end
    end
end

% Look for the Atlases!
list_atlas = dir(fullfile(dir_batch_templates, '*Atlas*.nii'));
if length(list_atlas) == 0
    pseudo_CT_output('ERROR', output_context, 'No atlas NIfTI files were found.');
    pseudo_CT_output('INFO', output_context, '    %s', dir_batch_templates);
    early_return = true;
    P_out = P;
    handoff = local_build_handoff('', dir_batch_templates, false, false, false, '', code_version, headless);
    return;
end

% To work only with the MPRAGE even if there are more files available!
P = P(1, :);

nf = size(P, 1); % nf = The total number of files to use.

if ~headless
    % Legacy interactive figure window; forbidden on the headless path.
    if ~isdeployed
        fh = spm('CreateIntWin', 'on');
        try
            set(fh, 'Visible', 'off');
        catch
        end
    else
        try
            fh = openfig('spm_Interactive.fig', 'new', 'visible');
            set(fh, 'Visible', 'off');
        catch
        end
    end
else
    fh = [];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Need to check whether the images are all in the same space! If not, ask
% the user to reslice them so that they all are in the same space.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
V = spm_vol(P);
resl = 1; % Do not reslice unless necessary:

% Define the flags for reslicing:
flg.mean  = 0; % Don't create a mean image;
flg.which = 1; % Don't reslice the first image;
flg.mask  = 0; % Don't mask;
flg.interp = 7; % 7th degree bspline;
flg.wrap = [0 0 0]; % No wrapping;

for ii = 2:nf
    if sum(V(ii).dim ~= V(ii-1).dim) > 0, resl = 1; break; end
end
if resl & nf > 1
    pseudo_CT_output('INFO', output_context, 'Reslicing inputs into MPRAGE space.');
    % The first image would be considered as reference, and the last as
    % source and the rest os other:
    job.ref = {deblank(P(1, :))}; job.source = {deblank(P(nf, :))}; job.other = {''};
    for ii = nf:-1:2
        job.other{ii-1, 1} = P(ii, :);
    end
    job.eoptions = spm_get_defaults('coreg.estimate'); job.roptions = spm_get_defaults('coreg.write');
    job.roptions.interp = 7; % 7th degree bspline;
    evalc('spm_run_coreg_estwrite(job);'); % Estimate and reslice!
    for ii = 2:nf
        [pathr, fnr, extr] = fileparts(deblank(P(ii, :)));
        aux = strcat(pathr, filesep, 'r', fnr, extr);
        P(ii, 1:length(aux)) = aux; % Just in case the new name is longer than the matrix P!
    end
    V = spm_vol(P); % Update the volume content with the new files!
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% v.1.8: Let's try to get the subject into the center of the image to avoid
% that the normalization process cut the nose
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if isempty(recenter_override)
    if isfield(config, 'recenter_before_normalization')
        recenter_before_normalization = config.recenter_before_normalization;
    else
        recenter_before_normalization = false;
    end
else
    recenter_before_normalization = recenter_override;
end
recenter_before_normalization = local_normalize_flag( ...
    recenter_before_normalization, false);

aliasing_requested = logical(check_aliasing);
recentering_requested = recenter_before_normalization;
gate_condition = length(strfind(deblank(P(1, :)), '_normalized.nii')) == 0 & ...
                 length(strfind(deblank(P(1, :)), '_moved.nii')) == 0;

if (aliasing_requested || recentering_requested) && gate_condition
    if ~local_correct_aliasing_supported()
        % The external facade requires MATLAB R2019+. Do not call it or
        % inspect its result on older releases; continue with original P.
        release = version('-release');
        if recentering_requested
            pseudo_CT_output('WARN', local_stage_context(output_context, 1), ...
                '[recentering] Unavailable: correct_aliasing requires MATLAB R2019+ (running R%s).', release);
        end
        if aliasing_requested
            pseudo_CT_output('WARN', local_stage_context(output_context, 1), ...
                '[aliasing correction] Unavailable: correct_aliasing requires MATLAB R2019+ (running R%s).', release);
        end
        if ~recentering_requested
            pseudo_CT_output('INFO', local_stage_context(output_context, 1), '[recentering] Skipped as configured.');
        end
        if ~aliasing_requested
            pseudo_CT_output('INFO', local_stage_context(output_context, 1), '[aliasing correction] Skipped as configured.');
        end
    else
    % Use external correct_aliasing package for independent alias correction
    % and centering.
    [path_in, name_in, ext_in] = fileparts(deblank(P(1, :)));
    output_path = fullfile(path_in, [name_in, '_corrected', ext_in]);

    result = correct_aliasing(deblank(P(1, :)), output_path, ...
        'AliasCorrection', aliasing_requested, ...
        'Centering', recentering_requested, ...
        'Overwrite', true);

    % Defensively normalize facade result
    result_status = '';
    result_message = '';
    result_outputs = {};
    result_details = struct();
    if isstruct(result)
        if isfield(result, 'status')
            if ischar(result.status)
                result_status = strtrim(result.status);
            elseif isnumeric(result.status) && ~isempty(result.status)
                result_status = strtrim(char(result.status));
            end
        end
        if isfield(result, 'message')
            if ischar(result.message)
                result_message = strtrim(result.message);
            elseif isnumeric(result.message) && ~isempty(result.message)
                result_message = strtrim(char(result.message));
            end
        end
        if isfield(result, 'outputs') && iscell(result.outputs)
            result_outputs = result.outputs;
        end
        if isfield(result, 'details') && isstruct(result.details)
            result_details = result.details;
        end
    end

    accepted = strcmpi(result_status, 'success') || strcmpi(result_status, 'partial');
    has_output = false;
    if ~isempty(result_outputs)
        candidate = result_outputs{1};
        if ischar(candidate) && ~isempty(strtrim(candidate))
            has_output = true;
        end
    end

    if accepted && has_output
        P = result.outputs{1};
    end

    % Log recentering outcome
    stage_ctx = local_stage_context(output_context, 1);
    if ~recentering_requested
        pseudo_CT_output('INFO', stage_ctx, '[recentering] Skipped as configured.');
    elseif accepted && has_output
        recentering_performed = [];
        if isfield(result_details, 'centering') && isstruct(result_details.centering) && isfield(result_details.centering, 'performed')
            raw = result_details.centering.performed;
            if islogical(raw)
                recentering_performed = raw;
            elseif isnumeric(raw) && ~isempty(raw)
                recentering_performed = logical(raw(1));
            elseif ischar(raw)
                trimmed = strtrim(raw);
                if strcmpi(trimmed, 'true') || strcmp(trimmed, '1')
                    recentering_performed = true;
                elseif strcmpi(trimmed, 'false') || strcmp(trimmed, '0')
                    recentering_performed = false;
                end
            end
        end
        if isempty(recentering_performed)
            pseudo_CT_output('WARN', stage_ctx, '[recentering] Result unavailable.');
        elseif recentering_performed
            pseudo_CT_output('SUCCESS', stage_ctx, '[recentering] Successfully applied.');
        else
            pseudo_CT_output('INFO', stage_ctx, '[recentering] Not required.');
        end
    else
        error_msg = result_message;
        if isempty(error_msg)
            error_msg = result_status;
        end
        if isempty(error_msg)
            error_msg = 'unknown';
        end
        pseudo_CT_output('ERROR', stage_ctx, '[recentering] Failed: %s.', error_msg);
    end

    % Log aliasing outcome
    if ~aliasing_requested
        pseudo_CT_output('INFO', stage_ctx, '[aliasing correction] Skipped as configured.');
    elseif accepted && has_output
        aliasing_performed = [];
        if isfield(result_details, 'alias_correction') && isstruct(result_details.alias_correction) && isfield(result_details.alias_correction, 'performed')
            raw = result_details.alias_correction.performed;
            if islogical(raw)
                aliasing_performed = raw;
            elseif isnumeric(raw) && ~isempty(raw)
                aliasing_performed = logical(raw(1));
            elseif ischar(raw)
                trimmed = strtrim(raw);
                if strcmpi(trimmed, 'true') || strcmp(trimmed, '1')
                    aliasing_performed = true;
                elseif strcmpi(trimmed, 'false') || strcmp(trimmed, '0')
                    aliasing_performed = false;
                end
            end
        end
        if isempty(aliasing_performed)
            pseudo_CT_output('WARN', stage_ctx, '[aliasing correction] Result unavailable.');
        elseif aliasing_performed
            pseudo_CT_output('SUCCESS', stage_ctx, '[aliasing correction] Successfully applied.');
        else
            pseudo_CT_output('INFO', stage_ctx, '[aliasing correction] Not required.');
        end
    else
        error_msg = result_message;
        if isempty(error_msg)
            error_msg = result_status;
        end
        if isempty(error_msg)
            error_msg = 'unknown';
        end
        pseudo_CT_output('ERROR', stage_ctx, '[aliasing correction] Failed: %s.', error_msg);
    end

    % Preserve early-return behavior
    if ~accepted || ~has_output
        P_out = P;
        handoff = local_build_handoff(deblank(P(1, :)), dir_batch_templates, ...
            aliasing_requested, recentering_requested, true, '', code_version, headless);
        early_return = true;
        return;
    end
    end
elseif ~recentering_requested
    stage_ctx = local_stage_context(output_context, 1);
    pseudo_CT_output('INFO', stage_ctx, '[recentering] Skipped as configured.');
    if aliasing_requested
        pseudo_CT_output('INFO', stage_ctx, '[aliasing correction] Skipped because pre-normalization preprocessing is disabled.');
    else
        pseudo_CT_output('INFO', stage_ctx, '[aliasing correction] Skipped as configured.');
    end
end

P_out = P;
selected = deblank(P(1, :));
needs_norm = length(strfind(selected, '_normalized.nii')) == 0;
normalized_expected = local_expected_normalized(selected);
handoff = local_build_handoff(selected, dir_batch_templates, ...
    aliasing_requested, recentering_requested, needs_norm, ...
    normalized_expected, code_version, headless);
return
end

function handoff = local_build_handoff(selected, atlas_dir, aliasing_eff, recenter_eff, needs_norm, normalized_expected, code_version, headless)
handoff = struct();
handoff.schema = 'pseudo-CT.current-handoff/v1';
handoff.input_selected = selected;
handoff.atlas_dir = atlas_dir;
handoff.aliasing_effective = logical(aliasing_eff);
handoff.recenter_effective = logical(recenter_eff);
handoff.needs_normalization = logical(needs_norm);
handoff.normalized_expected = normalized_expected;
handoff.code_version = code_version;
handoff.headless = logical(headless);
end

function expected = local_expected_normalized(selected)
expected = '';
if isempty(selected) || ~ischar(selected)
    return;
end
[pathn, namen, extn] = fileparts(selected);
if strcmp(extn(end-1:end), ',1')
    extn = extn(1:end-2);
end
if isempty(extn)
    extn = '.nii';
end
expected = fullfile(pathn, [namen, '_normalized', extn]);
end

function value = local_headless_enabled(config, output_context)
value = false;
candidates = {};
if isstruct(config) && isfield(config, 'headless')
    candidates{end + 1} = config.headless; %#ok<AGROW>
end
if isstruct(output_context) && isfield(output_context, 'headless')
    candidates{end + 1} = output_context.headless; %#ok<AGROW>
end
for ii = 1:length(candidates)
    raw = candidates{ii};
    if islogical(raw) && isscalar(raw) && ~isempty(raw)
        if raw
            value = true;
            return;
        end
    elseif isnumeric(raw) && isscalar(raw) && isfinite(raw)
        if double(raw) == 1
            value = true;
            return;
        end
    elseif ischar(raw) && size(raw, 1) == 1
        trimmed = lower(strtrim(raw));
        if strcmp(trimmed, 'yes') || strcmp(trimmed, 'true') || ...
                strcmp(trimmed, 'on') || strcmp(trimmed, '1')
            value = true;
            return;
        end
    end
end
end

function local_ensure_spm_headless()
% Bundled SPM initialization for noninteractive batch execution. No GUI,
% no prompts, no figure windows.
try
    spm('Defaults', 'FMRI');
catch ME
    error('pseudo_CT:HeadlessSPMUnavailable', ...
        'Bundled SPM initialization failed: %s', ME.message);
end
if exist('spm_jobman', 'file') == 2
    try
        spm_jobman('initcfg');
    catch ME
        error('pseudo_CT:HeadlessSPMUnavailable', ...
            'Bundled SPM batch initialization failed: %s', ME.message);
    end
else
    error('pseudo_CT:HeadlessSPMUnavailable', ...
        'Bundled SPM batch system (spm_jobman) is unavailable.');
end
if exist('cfg_util', 'file') ~= 2
    error('pseudo_CT:HeadlessSPMUnavailable', ...
        'Bundled SPM batch runner (cfg_util) is unavailable.');
end
end

function code_version = local_resolve_code_version()
code_version = '2.8.4';  % fallback
try
    root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    fid = fopen(fullfile(root_dir, 'CHANGELOG.md'), 'r');
    if fid ~= -1
        v = strtrim(fgetl(fid));
        fclose(fid);
        if ~isempty(v) && ischar(v)
            code_version = v;
        end
    end
catch %#ok<CTCH>
end
end

function context = local_stage_context(context, stage_index)
context.stage_index = stage_index;
context.stage_count = 8;
end

function value = local_normalize_flag(value, default_value)
if nargin < 1 || isempty(value)
    value = default_value;
elseif ischar(value)
    normalized = lower(strtrim(value));
    if strcmp(normalized, 'yes') || strcmp(normalized, 'true') || ...
            strcmp(normalized, 'on') || strcmp(normalized, '1')
        value = true;
    elseif strcmp(normalized, 'no') || strcmp(normalized, 'false') || ...
            strcmp(normalized, 'off') || strcmp(normalized, '0')
        value = false;
    else
        error('pseudo_CT:InvalidRecentering', ...
            'Recentering must be Yes/No or a scalar logical 0 or 1.');
    end
elseif (isnumeric(value) || islogical(value)) && isscalar(value) && ...
        (double(value) == 0 || double(value) == 1)
    value = logical(value);
else
    error('pseudo_CT:InvalidRecentering', ...
        'Recentering must be Yes/No or a scalar logical 0 or 1.');
end
end

function supported = local_correct_aliasing_supported()
release = version('-release');
supported = false;
if ischar(release)
    release_text = release;
    if ~isempty(release_text) && ...
            (release_text(1) == 'R' || release_text(1) == 'r')
        release_text = release_text(2:end);
    end
    if length(release_text) >= 4
        release_year = str2double(release_text(1:4));
        supported = ~isnan(release_year) && release_year >= 2019;
    end
end
end
