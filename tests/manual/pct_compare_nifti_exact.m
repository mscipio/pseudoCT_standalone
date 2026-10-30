function [is_equal, report] = pct_compare_nifti_exact(varargin)
%PCT_COMPARE_NIFTI_EXACT Exact semantic comparison of prepared NIfTI data.
%   [IS_EQUAL, REPORT] = PCT_COMPARE_NIFTI_EXACT(LEFT, RIGHT [, LIMIT])
%   accepts artifact structs with .header (or .hdr), .raw, and .scaled.
%
%   The six-input form accepts HDR_LEFT, HDR_RIGHT, RAW_LEFT, RAW_RIGHT,
%   SCALED_LEFT, SCALED_RIGHT, followed by an optional LIMIT. Headers use
%   SPM fields dim, dt (datatype/endian), pinfo (scaling), and mat (affine).
%   Filename/private fields are deliberately excluded. R2010b compatible.

[left, right, limit] = parse_inputs(varargin{:});
required = {'dim', 'dt', 'pinfo', 'mat'};
for i = 1:numel(required)
    name = required{i};
    left_has = isfield(left.header, name);
    right_has = isfield(right.header, name);
    if ~left_has || ~right_has
        [is_equal, report] = missing_header_report(name, left_has, right_has, limit);
        return
    end
end

header_fields = {'dim', 'dt', 'pinfo', 'mat', 'mat0', 'n', ...
    'datatype', 'endian', 'scl_slope', 'scl_inter', 'pixdim', ...
    'qform_code', 'sform_code', 'quatern_b', 'quatern_c', 'quatern_d', ...
    'qoffset_x', 'qoffset_y', 'qoffset_z', 'srow_x', 'srow_y', 'srow_z'};
left_header = select_header_fields(left.header, right.header, header_fields);
right_header = select_header_fields(right.header, left.header, header_fields);

left_value = struct('header', left_header, 'raw', left.raw, 'scaled', left.scaled);
right_value = struct('header', right_header, 'raw', right.raw, 'scaled', right.scaled);
[is_equal, report] = pct_compare_semantic_mat(left_value, right_value, {}, limit);
if is_equal
    report.summary = 'IDENTICAL: NIfTI header, raw data, and scaled data match exactly';
else
    report.summary = ['NIfTI ' report.summary];
end
end

function [left, right, limit] = parse_inputs(varargin)
limit = 10;
if nargin == 2 || nargin == 3
    left = normalize_artifact(varargin{1});
    right = normalize_artifact(varargin{2});
    if nargin == 3, limit = varargin{3}; end
elseif nargin == 6 || nargin == 7
    left = struct('header', varargin{1}, 'raw', varargin{3}, 'scaled', varargin{5});
    right = struct('header', varargin{2}, 'raw', varargin{4}, 'scaled', varargin{6});
    if nargin == 7, limit = varargin{7}; end
else
    error('pct_compare_nifti_exact:InvalidInputs', ...
        'Use two artifact structs or six header/raw/scaled inputs.');
end
end

function artifact = normalize_artifact(artifact)
if ~isstruct(artifact) || numel(artifact) ~= 1
    error('pct_compare_nifti_exact:InvalidArtifact', ...
        'Each artifact must be a scalar struct.');
end
if ~isfield(artifact, 'header') && isfield(artifact, 'hdr')
    artifact.header = artifact.hdr;
end
if ~all(isfield(artifact, {'header', 'raw', 'scaled'}))
    error('pct_compare_nifti_exact:InvalidArtifact', ...
        'Artifacts require header (or hdr), raw, and scaled fields.');
end
end

function selected = select_header_fields(header, other, names)
selected = struct();
for i = 1:numel(names)
    name = names{i};
    if isfield(header, name)
        selected.(name) = header.(name);
    elseif isfield(other, name)
        selected.(['missing_' name]) = true;
    end
end
end

function [is_equal, report] = missing_header_report(name, left_has, right_has, limit)
is_equal = false;
expected = presence_text(left_has);
actual = presence_text(right_has);
if ~left_has && ~right_has
    expected = 'required-but-missing';
    actual = 'required-but-missing';
end
difference = struct('path', ['root.header.' name], 'index', '', ...
    'expected', expected, 'actual', actual, 'state', 'required_field');
report.equal = false;
report.max_differences = limit;
report.limit_reached = false;
report.differences = difference;
report.first_difference = difference;
report.summary = sprintf('NIfTI DIVERGENT: required header field %s is unavailable', name);
end

function text = presence_text(value)
if value
    text = 'present';
else
    text = 'missing';
end
end
