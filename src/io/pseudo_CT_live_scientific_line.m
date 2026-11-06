function [handled, events] = pseudo_CT_live_scientific_line(line, path, version, context, holder)
%PSEUDO_CT_LIVE_SCIENTIFIC_LINE Adapt an existing backend byte collector.
% Interpretation is shared with read-only replay, never with lifecycle logs.
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
