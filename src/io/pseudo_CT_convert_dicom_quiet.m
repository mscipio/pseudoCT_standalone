function seed_nii = pseudo_CT_convert_dicom_quiet(input_file, output_file, context)
%PSEUDO_CT_CONVERT_DICOM_QUIET Run dcm2nii with its console output kept off the table.
%   dcm2nii (a MATLAB package) prints its own bracketed [dcm2nii] lines with
%   FPRINTF(1,...) in this MATLAB process, so EVALC captures them.  They are
%   re-recorded line by line, with the converter's own level and time, through
%   PSEUDO_CT_OUTPUT into the subject run log (console_detail_only keeps them
%   away from the shared presenter in CLI mode, text and JSONL).  Lines are
%   credential-redacted before they are persisted.  A conversion error is
%   rethrown unchanged after its captured output has been recorded.
conversion_error = [];
seed_nii = '';
% The try/catch lives inside EVALC so converter output printed before a
% failure is still captured (EVALC discards its text when it itself errors).
captured = evalc(['try, seed_nii = dcm2nii(input_file, output_file, ', ...
    '''Overwrite'', true); catch conversion_error, end']);
detail_context = context;
detail_context.console_detail_only = true;
% Raw converter output is run-log (LOG) only; it is never a JSONL diagnostic.
detail_context.raw_diagnostic = true;
lines = regexp(captured, '\r?\n', 'split');
for ii = 1:length(lines)
    text = strtrim(lines{ii});
    if isempty(text)
        continue;
    end
    level = 'INFO';
    detail_context.record_timestamp = '';
    token = regexp(text, ...
        ['^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\]', ...
         '[ \t]+(INFO|WARN|ERROR|SUCCESS)[ \t]+(.*)$'], 'tokens', 'once');
    if ~isempty(token)
        detail_context.record_timestamp = token{1};
        level = token{2};
        text = token{3};
    end
    % Same DICOM, path, host and credential rules as the console presenter.
    text = pseudo_CT_sanitize_message(text);
    pseudo_CT_output(level, detail_context, '%s', text);
end
if ~isempty(conversion_error)
    rethrow(conversion_error);
end
end
