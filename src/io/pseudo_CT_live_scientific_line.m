function [handled, events] = pseudo_CT_live_scientific_line(line, path, version, context, holder)
%PSEUDO_CT_LIVE_SCIENTIFIC_LINE Parse one live scientific line from a backend stream.
%   [HANDLED, EVENTS] = PSEUDO_CT_LIVE_SCIENTIFIC_LINE(LINE, PATH, VERSION, CONTEXT, HOLDER)
%   LINE is one text line from the running backend. PATH and VERSION identify
%   its source and format version. CONTEXT supplies the subject index used in
%   the subject label. HOLDER is a containers.Map that keeps parser state
%   between calls under the key 'scientific_parser'.
%   EVENTS are the parsed events whose status is not WARN or ERROR; the live
%   console formatter shows those itself, so they are not shown twice. HANDLED
%   is true when EVENTS is not empty. Interpretation matches the read-only
%   replay parser (pseudo_CT_parse_scientific_lines).
%   Side effects: updates HOLDER only. Minimum supported MATLAB: R2010b.
subject = 'subject';
if isfield(context, 'subject_index')
    subject = sprintf('subject %d', context.subject_index);
end
state = [];
if holder.isKey('scientific_parser'), state = holder('scientific_parser'); end
[events, state] = pseudo_CT_parse_scientific_lines({line}, path, version, subject, state);
holder('scientific_parser') = state;
% Existing live diagnostic grouping/formatting remains authoritative. Do not
% render warning/error events twice; replay still returns their full schema.
keep = true(size(events));
for ii = 1:length(events)
    keep(ii) = ~any(strcmp(events(ii).status, {'WARN'; 'ERROR'}));
end
events = events(keep);
handled = ~isempty(events);
end
