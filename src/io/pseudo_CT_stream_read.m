function [lines, state] = pseudo_CT_stream_read(path, state, final)
%PSEUDO_CT_STREAM_READ Read a byte snapshot once; hold partial lines until EOF.
% STATE owns path/offset/buffer/line_count. FINAL declares producer EOF, not a
% temporary growing-file EOF. A second unchanged/final poll returns no lines.
if nargin < 2 || isempty(state)
    state = struct('path', path, 'offset', 0, 'buffer', '', 'line_count', 0);
end
if nargin < 3, final = false; end
if ~strcmp(state.path, path)
    error('pseudo_CT:StreamPath', 'A reader cannot switch source files.');
end
lines = {};
fid = fopen(path, 'rb');
if fid ~= -1
    guard = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fseek(fid, 0, 'eof');
    last = ftell(fid);
    if last < state.offset
        error('pseudo_CT:StreamTruncated', 'Scientific source was truncated; refusing duplicate replay.');
    end
    if fseek(fid, state.offset, 'bof') ~= 0
        error('pseudo_CT:StreamSeek', 'Cannot seek scientific source.');
    end
    bytes = fread(fid, last - state.offset, '*uint8');
    state.offset = state.offset + length(bytes);
    state.buffer = [state.buffer char(bytes(:)')];
end
cuts = find(state.buffer == char(10));
first = 1;
for ii = 1:length(cuts)
    lines{end + 1} = state.buffer(first:cuts(ii)-1); %#ok<AGROW>
    first = cuts(ii) + 1;
end
state.buffer = state.buffer(first:end);
if final && ~isempty(state.buffer)
    lines{end + 1} = state.buffer;
    state.buffer = '';
end
for ii = 1:length(lines)
    if ~isempty(lines{ii}) && lines{ii}(end) == char(13)
        lines{ii}(end) = '';
    end
end
state.line_count = state.line_count + length(lines);
end
