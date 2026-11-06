function out = pseudo_CT_json_escape(text)
%PSEUDO_CT_JSON_ESCAPE Escape char text for use inside a JSON string literal.
%   OUT = PSEUDO_CT_JSON_ESCAPE(TEXT) escapes backslash and double quote, uses
%   the short forms \n \r \t, and writes every other character outside the
%   printable ASCII range (controls below 0x20, DEL, and anything above 0x7E)
%   as \uXXXX. The output is therefore pure 7-bit ASCII and independent of the
%   MATLAB session encoding. Minimum supported MATLAB: R2010b.

if ~ischar(text)
    error('pseudo_CT:JsonEscape', 'JSON string text must be char.');
end
out = '';
if isempty(text)
    return;
end
pieces = cell(1, numel(text));
for ii = 1:numel(text)
    code = double(text(ii));
    switch code
        case 92     % backslash
            pieces{ii} = '\\';
        case 34     % double quote
            pieces{ii} = '\"';
        case 10     % line feed
            pieces{ii} = '\n';
        case 13     % carriage return
            pieces{ii} = '\r';
        case 9      % tab
            pieces{ii} = '\t';
        otherwise
            if code < 32 || code > 126
                pieces{ii} = sprintf('\\u%04x', code);
            else
                pieces{ii} = text(ii);
            end
    end
end
out = [pieces{:}];
end
