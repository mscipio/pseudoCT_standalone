function pseudo_CT_present_scientific_events(events, context)
%PSEUDO_CT_PRESENT_SCIENTIFIC_EVENTS Show native scientific stage events.
%   PSEUDO_CT_PRESENT_SCIENTIFIC_EVENTS(EVENTS, CONTEXT) shows each record of
%   EVENTS, as read by pseudo_CT_scientific_event_read, through
%   pseudo_CT_output_console_visible, the one console boundary for stage rows.
%   Records are shown exactly as persisted: no transition is inferred. The
%   JSONL view is emitted by that same boundary (PSEUDOCT_OUTPUT_FORMAT=jsonl),
%   so text and JSONL show the same admitted events.
%   Side effects: prints to the console. Minimum supported MATLAB: R2010b.
if nargin < 2, context = struct(); end
for ii = 1:length(events)
    event = events(ii);
    ctx = context;
    ctx.workflow_event = true; % stage is already canonical, never producer-map
    ctx.direct_scientific_stream = true;
    ctx.stage_index = event.stage.index; ctx.stage_count = 10;
    ctx.stage_status = event.status;
    ctx.stage_message = event.message;
    ctx.source = 'backend'; ctx.source_file = event.source.file;
    level = 'INFO';
    if any(strcmp(event.status, {'WARN'; 'ERROR'})), level = event.status; end
    message = event.message;
    if ~isempty(event.source_timestamp)
        message = ['[' event.source_timestamp '] ' level ' ' message];
    end
    [visible, text] = pseudo_CT_output_console_visible(level, message, ctx);
    if visible && ~strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
        fprintf(1, '%s\n', text);
    end
end
end
