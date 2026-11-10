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
% Archived replay: the caller passes context.live = false. Only then the record's
% own UTC time prefixes the row and its native source is kept; live rows are unchanged.
archived = isfield(context, 'live') && (islogical(context.live) || isnumeric(context.live)) && ...
    isscalar(context.live) && isfinite(double(context.live)) && ~context.live;
for ii = 1:length(events)
    event = events(ii);
    ctx = context;
    ctx.workflow_event = true; % stage is already canonical, never producer-map
    ctx.direct_scientific_stream = true;
    ctx.stage_index = event.stage.index; ctx.stage_count = 10;
    ctx.stage_status = event.status;
    ctx.stage_message = event.message;
    ctx.native_stage_id = event.native_stage_id;
    ctx.source = 'backend'; ctx.source_file = event.source.file;
    if archived && ~isempty(event.source.version) && ~strcmp(event.source.version, 'native')
        ctx.source = event.source.version;
    end
    level = 'INFO';
    if any(strcmp(event.status, {'WARN'; 'ERROR'})), level = event.status; end
    message = event.message;
    if archived && ~isempty(event.source_timestamp)
        message = ['[' event.source_timestamp '] ' level ' ' message];
    end
    [visible, text] = pseudo_CT_output_console_visible(level, message, ctx);
    if visible && ~strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
        fprintf(1, '%s\n', text);
    end
end
end
