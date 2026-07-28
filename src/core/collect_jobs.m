function [jobs, stats] = collect_jobs(config, varargin)
%COLLECT_JOBS Collect pseudo-CT jobs from GUI, batch mode, or subject list.
%   JOBS = COLLECT_JOBS(MANIFEST) opens the existing single-subject GUI
%   (LOAD_MR_4_AC) and returns a job struct for one subject.
%
%   JOBS = COLLECT_JOBS(MANIFEST, 'batch') opens an SPM multi-select file
%   picker for MPRAGE files and returns a job struct array with one entry
%   per selected subject.
%
%   JOBS = COLLECT_JOBS(MANIFEST, SUBJECT_LIST) processes an explicit list
%   of MPRAGE files. SUBJECT_LIST can be:
%       - a cell array of filenames
%       - a char matrix with one filename per row
%       - a single MPRAGE filename
%
%   JOBS = COLLECT_JOBS(MANIFEST, SUBJECT_LIST, CORRECT_ALIASING) overrides
%   the anti-aliasing flag. CORRECT_ALIASING should be numeric or logical:
%   use 1/true to enable the correction and 0/false to disable it.
%
%   CONFIG is the selected profile config.
%
%   Returns a struct array with fields: mprage_fn, umap_fn, correct_aliasing.
%   Returns empty when the GUI is cancelled or when no subjects are provided.
%
%   Minimum supported MATLAB: R2010b.

jobs = struct('mprage_fn', {}, 'umap_fn', {}, 'correct_aliasing', {});
stats = struct('requested', 0, 'skipped', 0, 'skipped_subjects', {{}});

if ~isdeployed && ~isempty(varargin)
    subject_list = '';
    if ischar(varargin{1}) && strcmpi(strtrim(varargin{1}), 'batch')
        subject_list = spm_select(Inf, '*', ...
            'Select the MPRAGE files to use to obtain atlas-based attenuation maps');
    elseif iscell(varargin{1})
        subject_list = char(varargin{1});
    elseif ischar(varargin{1}) && size(varargin{1}, 1) > 1
        subject_list = varargin{1};
    elseif ischar(varargin{1}) && exist(strtrim(varargin{1}), 'file') == 2
        subject_list = char(varargin{1});
    end

    if ~isempty(subject_list)
        correct_aliasing = config.aliasing_default;
        if numel(varargin) > 1
            correct_aliasing = varargin{2};
        end
        correct_aliasing = validate_aliasing(correct_aliasing);
        [jobs, stats] = build_jobs_from_subject_list(subject_list, correct_aliasing);
        return;
    end
end

[mprage_fn, ute_fn, umap_fn, correct_aliasing] = load_mr_4_AC('mMR');

if mprage_fn == 0
    return;
end
if ~ischar(mprage_fn) || ~ischar(ute_fn) || ~ischar(umap_fn)
    warndlg('There are some of the filenames missing', 'Files missing!');
    return
end

correct_aliasing = validate_aliasing(correct_aliasing);

jobs(1).mprage_fn = mprage_fn;
jobs(1).umap_fn = umap_fn;
jobs(1).correct_aliasing = correct_aliasing;
stats.requested = 1;

end

function value = validate_aliasing(value)
if ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ...
        ~ismember(double(value), [0 1])
    error('pseudo_CT:InvalidAliasing', ...
        'Aliasing correction must be a scalar numeric or logical 0 or 1.');
end
value = double(value);
end
