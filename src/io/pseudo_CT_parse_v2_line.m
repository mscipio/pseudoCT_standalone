function [stage, status, kind] = pseudo_CT_parse_v2_line(message)
%PSEUDO_CT_PARSE_V2_LINE Interpret only evidenced legacy compiled markers.
stage = 0; status = ''; kind = 'explicit';
if strcmp(message, 'Opening the Template and calculating its position in real space ...')
    stage = 5; status = 'INFO'; kind = 'inferred';
elseif ~isempty(regexp(message, '^Opening file: .+ and calculating the mask \.\.\.$', 'once'))
    stage = 5; status = 'START';
elseif strcmp(message, 'Starting the New Segment process (be patient!!) ...') || ...
        strcmp(message, 'Running ''New Segment''')
    stage = 6; status = 'START';
elseif ~isempty(regexp(message, '^Done\s+''New Segment''$', 'once'))
    stage = 6; status = 'DONE';
elseif strcmp(message, 'Running ''Run DARTEL (existing Templates)''')
    stage = 7; status = 'START';
elseif ~isempty(regexp(message, '^(Running|Done)\s+''(Run DARTEL \(existing Templates\)|Create Inverse Warped)''$', 'once')) || ...
        ~isempty(strfind(message, 'Starting the final reslicing of the atlas'))
    stage = 7; status = 'INFO';
elseif ~isempty(strfind(message, 'Coregistration and reslicing finished'))
    stage = 7; status = 'DONE';
elseif ~isempty(strfind(message, 'Creating att_map file'))
    stage = 8; status = 'START';
elseif strncmp(message, 'Attenuation map file created', 28) || strncmp(message, 'Whole process finished', 22)
    stage = 8; status = 'INFO'; % not independent evidence of QC completion
end
% No mapping from the opaque legacy producer stage 3 to DONE(5:8).
end
