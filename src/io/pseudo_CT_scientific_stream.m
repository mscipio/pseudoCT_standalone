function [events, state] = pseudo_CT_scientific_stream(path, version, subject, state, final)
%PSEUDO_CT_SCIENTIFIC_STREAM Incremental direct-file v3 scientific parser.
% STATE contains the byte reader and version-specific interpretation state.
% FINAL=true declares EOF; false holds an unterminated growing-file line.
if nargin < 4 || isempty(state)
    state = struct('reader', [], 'parser', []);
end
if nargin < 5, final = false; end
[lines, state.reader] = pseudo_CT_stream_read(path, state.reader, final);
[events, state.parser] = pseudo_CT_parse_scientific_lines( ...
    lines, path, version, subject, state.parser);
end
