function events = pseudo_CT_present_native_events(output_context, enabled)
%PSEUDO_CT_PRESENT_NATIVE_EVENTS Read and show new records of one run file.
%   EVENTS = PSEUDO_CT_PRESENT_NATIVE_EVENTS(OUTPUT_CONTEXT, ENABLED) returns
%   the stage records appended since the previous call for this run's JSONL
%   file, restricted to OUTPUT_CONTEXT's subject. When ENABLED is true they are
%   shown through pseudo_CT_present_scientific_events. The read cursor is kept
%   per event file for the session, so every drain of one run (manager input,
%   pipeline monitoring, manager finalization) shares one cursor and no record
%   is shown twice. Reader errors propagate to the caller.
%   Minimum supported MATLAB: R2010b.

persistent cursors;
if ~isa(cursors, 'containers.Map')
    cursors = containers.Map();
end
events = [];
target = pseudo_CT_scientific_event_target(output_context);
if isempty(target.path)
    return;
end
key = target.path;
reader = [];
if isKey(cursors, key)
    reader = cursors(key);
end
[events, reader] = pseudo_CT_scientific_event_read(target.path, reader);
cursors(key) = reader;
if isfield(output_context, 'subject_index') && ~isempty(events)
    % Only this subject's records: the run file may hold other subjects' records.
    keep = strcmp({events.subject}', ...
        sprintf('subject-%d', output_context.subject_index));
    events = events(keep);
end
if enabled && ~isempty(events)
    pseudo_CT_present_scientific_events(events, output_context);
end
end
