function out = pseudo_CT_subjects_file(action, varargin)
%PSEUDO_CT_SUBJECTS_FILE Write the canonical subjects file (pseudoCT subjects v1).
%   TEXT = PSEUDO_CT_SUBJECTS_FILE('text', IDS, MPRAGE, UMAP) returns the file text for
%   the subjects IDS{k} with MPRAGE{k} and UMAP{k}. UMAP may be {} (MPRAGE-only profiles),
%   and an empty UMAP{k} writes no UMAP line for that subject.
%   PSEUDO_CT_SUBJECTS_FILE('write', PATH, IDS, MPRAGE, UMAP) writes that text to PATH
%   (UTF-8). OUT is PATH.
%
%   The grammar and every check of the content belong to the launcher's subjects-file
%   parser (bin/pseudoct check-subjects; grammar in docs/headless-cli.md). This writer
%   refuses only what the format cannot represent, so that the parser reads back exactly
%   the values given:
%     - identifiers: 1-64 letters, digits, '.', '_' or '-', starting with a letter or
%       digit, unique without regard to case (the [SubjectID] header syntax);
%     - paths: non-empty, one line, no NUL character.
%   A value is written between double quotes; between single quotes when it contains a
%   double quote; and without quotes when it contains both quote characters, which the
%   parser reads literally as long as the value neither starts with a quote nor has
%   leading or trailing blanks. Only a value that meets none of these forms is refused.
%   Paths are written as given: callers pass absolute paths (a relative path would be
%   resolved against the folder of the subjects file).
%   Minimum supported MATLAB: R2010b.

if nargin < 1 || ~ischar(action)
    error('pseudo_CT:SubjectsFileUsage', 'A subjects-file action is required.');
end
switch lower(action)
    case 'text'
        if numel(varargin) ~= 3
            error('pseudo_CT:SubjectsFileUsage', 'text needs IDS, MPRAGE and UMAP.');
        end
        out = local_text(varargin{1}, varargin{2}, varargin{3});
    case 'write'
        if numel(varargin) ~= 4
            error('pseudo_CT:SubjectsFileUsage', 'write needs PATH, IDS, MPRAGE and UMAP.');
        end
        text = local_text(varargin{2}, varargin{3}, varargin{4});
        local_write(varargin{1}, text);
        out = varargin{1};
    otherwise
        error('pseudo_CT:SubjectsFileUsage', 'Unknown subjects-file action.');
end
end

function text = local_text(ids, mprage, umap)
if ~iscell(ids) || ~iscell(mprage) || ~iscell(umap) || isempty(ids) || ...
        numel(ids) ~= numel(mprage) || (~isempty(umap) && numel(umap) ~= numel(ids))
    error('pseudo_CT:SubjectsFileUsage', ['The subject list needs one identifier and ' ...
        'one MPRAGE per subject, and a UMAP list of the same length or none.']);
end
lines = {'# pseudoCT subjects v1'};
seen = {};
for kk = 1:numel(ids)
    id = ids{kk};
    if ~ischar(id) || isempty(regexp(id, '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$', 'once'))
        error('pseudo_CT:SubjectsFileInvalid', ['Subject %d: the identifier must have 1 ' ...
            'to 64 letters, digits, ''.'', ''_'' or ''-'', starting with a letter or ' ...
            'digit.'], kk);
    end
    if any(strcmpi(seen, id))
        error('pseudo_CT:SubjectsFileInvalid', ...
            'Subject %d: the identifier %s is used twice (identifiers ignore letter case).', ...
            kk, id);
    end
    seen{end + 1} = id; %#ok<AGROW>
    lines{end + 1, 1} = ''; %#ok<AGROW>
    lines{end + 1, 1} = ['[' id ']']; %#ok<AGROW>
    lines{end + 1, 1} = ['MPRAGE = ' local_value(mprage{kk}, id, 'MPRAGE')]; %#ok<AGROW>
    if ~isempty(umap) && ~isempty(umap{kk})
        lines{end + 1, 1} = ['UMAP = ' local_value(umap{kk}, id, 'UMAP')]; %#ok<AGROW>
    end
end
text = '';
for kk = 1:numel(lines)
    text = [text lines{kk} char(10)]; %#ok<AGROW>
end
end

function value = local_value(path_text, id, label)
%LOCAL_VALUE One path as a field value the parser reads back unchanged.
if ~ischar(path_text) || isempty(path_text) || size(path_text, 1) ~= 1
    error('pseudo_CT:SubjectsFileInvalid', 'Subject %s: the %s path is empty.', id, label);
end
if any(path_text == char(10)) || any(path_text == char(13)) || any(path_text == char(0))
    error('pseudo_CT:SubjectsFileInvalid', ['Subject %s: the %s path contains a line ' ...
        'break or a NUL character, which a subjects file cannot hold.'], id, label);
end
dq = '"';
sq = char(39);
if ~any(path_text == dq)
    value = [dq path_text dq];
elseif ~any(path_text == sq)
    value = [sq path_text sq];
else
    % Both quote characters: the unquoted form is read literally unless the value starts
    % with a quote or has blanks (space, tab, form feed, vertical tab) at either end.
    blanks = [' ' char(9) char(12) char(11)];
    if any(path_text(1) == [dq sq]) || any(path_text(1) == blanks) || ...
            any(path_text(end) == blanks)
        error('pseudo_CT:SubjectsFileInvalid', ['Subject %s: the %s path contains both ' ...
            'quote characters and starts with a quote or has a leading or trailing ' ...
            'blank; a subjects file cannot represent it. Rename the file or folder.'], ...
            id, label);
    end
    value = path_text;
end
end

function local_write(path_text, text)
if ~ischar(path_text) || isempty(path_text)
    error('pseudo_CT:SubjectsFileUsage', 'A subjects-file path is required.');
end
fid = fopen(path_text, 'w', 'n', 'UTF-8');
if fid < 0
    error('pseudo_CT:SubjectsFileWrite', 'Cannot write the subjects file %s.', path_text);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s', text);
end
