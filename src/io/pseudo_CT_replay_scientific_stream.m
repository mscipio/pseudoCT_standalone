function [events, state] = pseudo_CT_replay_scientific_stream(path, version, subject, print_events)
%PSEUDO_CT_REPLAY_SCIENTIFIC_STREAM Read-only snapshot replay; no science.
% [EVENTS, STATE] = ...(PATH, 'v3', SUBJECT, PRINT_EVENTS)
% Growing sources: use pseudo_CT_scientific_stream(..., STATE, false) instead.
if nargin < 4, print_events = false; end
if exist(path, 'file') ~= 2
    error('pseudo_CT:StreamUnavailable', 'The scientific stream is unavailable.');
end
[events, state] = pseudo_CT_scientific_stream(path, version, subject, [], true);
if print_events
    pseudo_CT_output_console_visible('RESET');
    context = struct('live', false, 'console_profile', 'local-current');
    pseudo_CT_present_scientific_events(events, context);
end
end
