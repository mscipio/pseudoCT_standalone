function text = pseudo_CT_sanitize_message(text)
%PSEUDO_CT_SANITIZE_MESSAGE Redact DICOM names, paths, hosts and credentials.
%   Shared by the console presenter (PSEUDO_CT_OUTPUT_CONSOLE_VISIBLE) and the
%   dcm2nii converter helper (PSEUDO_CT_CONVERT_DICOM_QUIET), so both apply the
%   same path and credential rules before text is shown or persisted.
%   Minimum MATLAB: R2010b.
% Replace DICOM names and paths with stable short identifiers for routine
% console output. PSEUDO_CT_OUTPUT still writes the original source line.
dicom_names = regexp(text, ...
    '(?i)(?:[A-Za-z]:\\|/)?[^ \t,;:()]*\.dcm', 'match');
for ii = 1:length(dicom_names)
    identifier = local_short_hash(dicom_names{ii});
    text = strrep(text, dicom_names{ii}, ['DICOM-' identifier]);
end
% Redact path-shaped tokens only: absolute paths, and relative multi-segment
% tokens with a subject-data directory segment (MR_PET, MR, pseudo_muMAP, tmp)
% or a segment ending in a file extension; keep prose such as
% registration/warping and exactly the approved MR_PET/pseudoct-run-*.log
% disclosure. Mirrors bin/pseudoct.
boundary = '(?<![^\s=''"(\[<,;:])';
text = regexprep(text, [boundary '(?:~|\.{1,2})?/[^ \t,;:()]+'], '<path>');
text = regexprep(text, [boundary ...
    '(?!MR_PET/pseudoct-run-[0-9A-Za-z-]+\.log(?![\w.\-/]))' ...
    '(?=[\w.\-/]*?(?:(?<![\w.\-])(?:MR_PET|MR|pseudo_muMAP|tmp)(?![\w.\-])' ...
    '|\.(?=[0-9]*[A-Za-z])[A-Za-z0-9]{1,5}(?![\w.\-])))' ...
    '[\w.\-]+(?:/[\w.\-]+)+'], '<path>');
text = regexprep(text, '[A-Za-z]:\\[^ \t,;:()]+', '<path>');
% Cluster host names from remote warnings (site domain and compute-node names).
text = regexprep(text, ...
    '(?i)(username|user|password|passphrase|account|token|secret)([ \t]*[:=][ \t]*|[ \t]+)[^ \t,;]+', ...
    '$1$2<redacted>');
text = regexprep(text, '[\r\n]+', ' | ');
end

function identifier = local_short_hash(value)
% Compact deterministic display identifier; it is not a security primitive.
hash_value = 5381;
for ii = 1:length(value)
    hash_value = mod(hash_value * 33 + double(value(ii)), 4294967296);
end
identifier = lower(dec2hex(hash_value, 8));
end
