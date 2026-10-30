function [is_equal, report] = pct_compare_semantic_mat(left, right, path_map, max_differences)
%PCT_COMPARE_SEMANTIC_MAT Exact recursive comparison of MAT-file content.
%   [IS_EQUAL, REPORT] = PCT_COMPARE_SEMANTIC_MAT(LEFT, RIGHT, PATH_MAP, LIMIT)
%   compares loaded values or MAT filenames without comparing serialized bytes.
%   PATH_MAP is an N-by-2 cell array of canonical path and content identity.
%   Only character row vectors explicitly present in PATH_MAP are remapped.
%
%   REPORT.differences contains at most LIMIT deterministic entries with fields
%   path, index, expected, actual, and state. Minimum supported MATLAB: R2010b.

if nargin < 3 || isempty(path_map)
    path_map = cell(0, 2);
end
if nargin < 4 || isempty(max_differences)
    max_differences = 10;
end
if ~isnumeric(max_differences) || numel(max_differences) ~= 1 || ...
        ~isfinite(max_differences) || max_differences < 1 || ...
        max_differences ~= floor(max_differences)
    error('pct_compare_semantic_mat:InvalidLimit', ...
        'max_differences must be a positive integer.');
end

left = load_if_mat_file(left);
right = load_if_mat_file(right);
map = normalize_path_map(path_map);
state.limit = double(max_differences);
state.differences = empty_differences();
state = compare_value(left, right, 'root', state, map);

is_equal = isempty(state.differences);
report.equal = is_equal;
report.max_differences = state.limit;
report.limit_reached = numel(state.differences) == state.limit;
report.differences = state.differences;
if is_equal
    report.first_difference = empty_difference();
    report.summary = 'IDENTICAL: semantic MAT content matches exactly';
else
    report.first_difference = state.differences(1);
    report.summary = sprintf('DIVERGENT: %d difference(s) reported (limit %d); first %s [%s]', ...
        numel(state.differences), state.limit, ...
        report.first_difference.path, report.first_difference.state);
end
end

function value = load_if_mat_file(value)
if ischar(value) && size(value, 1) == 1 && exist(value, 'file') == 2
    value = load(value);
end
end

function map = normalize_path_map(path_map)
if isstruct(path_map)
    if ~all(isfield(path_map, {'path', 'content'}))
        error('pct_compare_semantic_mat:InvalidPathMap', ...
            'Struct path_map entries require path and content fields.');
    end
    map = cell(numel(path_map), 2);
    for i = 1:numel(path_map)
        map{i, 1} = path_map(i).path;
        map{i, 2} = path_map(i).content;
    end
else
    map = path_map;
end
if ~iscell(map) || size(map, 2) ~= 2
    error('pct_compare_semantic_mat:InvalidPathMap', ...
        'path_map must be an N-by-2 cell array or path/content struct array.');
end
for i = 1:size(map, 1)
    if ~ischar(map{i, 1}) || ~ischar(map{i, 2})
        error('pct_compare_semantic_mat:InvalidPathMap', ...
            'Path and content identities must be character arrays.');
    end
    map{i, 1} = canonical_path(map{i, 1});
end
end

function state = compare_value(a, b, path, state, map)
if at_limit(state)
    return
end
if ~strcmp(class(a), class(b))
    state = add_difference(state, path, '', class(a), class(b), 'class');
    return
end
if ischar(a) && size(a, 1) == 1 && size(b, 1) == 1
    left_id = mapped_content(a, map);
    right_id = mapped_content(b, map);
    if ~isempty(left_id) && ~isempty(right_id)
        if strcmp(left_id, right_id)
            return
        end
        state = add_difference(state, path, '', left_id, right_id, 'path_content');
        return
    end
end
if ~isequal(size(a), size(b))
    state = add_difference(state, path, '', mat2str(size(a)), ...
        mat2str(size(b)), 'shape');
    return
end

if isstruct(a)
    state = compare_struct(a, b, path, state, map);
elseif iscell(a)
    for i = 1:numel(a)
        state = compare_value(a{i}, b{i}, sprintf('%s{%d}', path, i), state, map);
        if at_limit(state), return; end
    end
elseif isnumeric(a)
    if isreal(a) ~= isreal(b)
        state = add_difference(state, path, '', logical_text(isreal(a)), ...
            logical_text(isreal(b)), 'complexity');
        return
    end
    state = compare_numeric_component(real(a), real(b), path, state);
    if ~isreal(a) && ~at_limit(state)
        state = compare_numeric_component(imag(a), imag(b), [path '.imag'], state);
    end
elseif ischar(a)
    if ~isequal(a, b)
        state = add_difference(state, path, '', bounded_text(a), ...
            bounded_text(b), 'value');
    end
elseif islogical(a)
    bad = find(a(:) ~= b(:));
    for i = 1:numel(bad)
        index = bad(i);
        state = add_difference(state, path, sprintf('%d', index), ...
            logical_text(a(index)), logical_text(b(index)), 'value');
        if at_limit(state), return; end
    end
elseif ~isequal(a, b)
    state = add_difference(state, path, '', class(a), class(b), 'value');
end
end

function state = compare_struct(a, b, path, state, map)
left_fields = sort(fieldnames(a));
right_fields = sort(fieldnames(b));
all_fields = unique([left_fields; right_fields]);
for f = 1:numel(all_fields)
    name = all_fields{f};
    in_left = any(strcmp(left_fields, name));
    in_right = any(strcmp(right_fields, name));
    field_path = [path '.' name];
    if ~in_left || ~in_right
        state = add_difference(state, field_path, '', ...
            presence_text(in_left), presence_text(in_right), 'field_presence');
    else
        for i = 1:numel(a)
            if numel(a) > 1
                item_path = sprintf('%s(%d).%s', path, i, name);
            else
                item_path = field_path;
            end
            state = compare_value(a(i).(name), b(i).(name), item_path, state, map);
            if at_limit(state), return; end
        end
    end
    if at_limit(state), return; end
end
end

function state = compare_numeric_component(a, b, path, state)
for i = 1:numel(a)
    expected_state = numeric_state(a(i));
    actual_state = numeric_state(b(i));
    if ~strcmp(expected_state, actual_state)
        state = add_difference(state, path, sprintf('%d', i), ...
            scalar_text(a(i)), scalar_text(b(i)), 'nonfinite_state');
    elseif strcmp(expected_state, 'finite')
        if a(i) ~= b(i)
            state = add_difference(state, path, sprintf('%d', i), ...
                scalar_text(a(i)), scalar_text(b(i)), 'finite_value');
        elseif a(i) == 0 && signed_zero_supported(a(i)) && ...
                zero_sign(a(i)) ~= zero_sign(b(i))
            state = add_difference(state, path, sprintf('%d', i), ...
                scalar_text(a(i)), scalar_text(b(i)), 'signed_zero');
        end
    end
    if at_limit(state), return; end
end
end

function text = numeric_state(value)
if isnan(value)
    text = 'nan';
elseif isinf(value) && value > 0
    text = '+inf';
elseif isinf(value)
    text = '-inf';
else
    text = 'finite';
end
end

function tf = signed_zero_supported(value)
tf = (isa(value, 'double') || isa(value, 'single')) && value == 0 && ...
    isinf(rdivide(1, value));
end

function value = zero_sign(value)
reciprocal = rdivide(1, value(1));
if reciprocal < 0
    value = -1;
else
    value = 1;
end
end

function content = mapped_content(path, map)
content = '';
key = canonical_path(path);
for i = 1:size(map, 1)
    if strcmp(key, map{i, 1})
        content = map{i, 2};
        return
    end
end
end

function path = canonical_path(path)
path = strrep(path, '\', '/');
while ~isempty(strfind(path, '//')) %#ok<STREMP>
    path = strrep(path, '//', '/');
end
while ~isempty(strfind(path, '/./')) %#ok<STREMP>
    path = strrep(path, '/./', '/');
end
if numel(path) > 1 && path(end) == '/'
    path = path(1:end-1);
end
end

function state = add_difference(state, path, index, expected, actual, kind)
if at_limit(state)
    return
end
difference = struct('path', path, 'index', index, ...
    'expected', expected, 'actual', actual, 'state', kind);
state.differences(end + 1) = difference;
end

function tf = at_limit(state)
tf = numel(state.differences) >= state.limit;
end

function text = scalar_text(value)
if isinteger(value)
    text = integer_scalar_text(value);
elseif isnan(value)
    text = 'NaN';
elseif isinf(value) && value > 0
    text = '+Inf';
elseif isinf(value)
    text = '-Inf';
elseif value == 0 && signed_zero_supported(value) && zero_sign(value) < 0
    text = '-0';
else
    text = sprintf('%.17g', double(value));
end
end

function text = integer_scalar_text(value)
is_negative = value < 0;
if is_negative
    one = feval(class(value), 1);
    magnitude = uint64(-(value + one)) + uint64(1);
else
    magnitude = uint64(value);
end
if magnitude == 0
    text = '0';
    return
end

text = '';
ten = uint64(10);
while magnitude > 0
    quotient = idivide(magnitude, ten, 'floor');
    remainder = magnitude - quotient * ten;
    text = [char(double(remainder) + double('0')) text]; %#ok<AGROW>
    magnitude = quotient;
end
if is_negative
    text = ['-' text];
end
end

function text = bounded_text(value)
limit = 80;
if numel(value) > limit
    text = [value(1:limit) '...'];
else
    text = value;
end
end

function text = logical_text(value)
if value
    text = 'true';
else
    text = 'false';
end
end

function text = presence_text(value)
if value
    text = 'present';
else
    text = 'missing';
end
end

function value = empty_difference()
value = struct('path', '', 'index', '', 'expected', '', ...
    'actual', '', 'state', '');
end

function values = empty_differences()
values = repmat(empty_difference(), 0, 1);
end
