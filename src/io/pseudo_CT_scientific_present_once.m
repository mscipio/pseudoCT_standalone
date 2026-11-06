function shown = pseudo_CT_scientific_present_once(events, shown, origin, native_capable, output_context, present_enabled)
%PSEUDO_CT_SCIENTIFIC_PRESENT_ONCE Choose one presentation source per stage.
%   SHOWN = PSEUDO_CT_SCIENTIFIC_PRESENT_ONCE(EVENTS, SHOWN, ORIGIN,
%   NATIVE_CAPABLE, OUTPUT_CONTEXT, PRESENT_ENABLED) presents presenter-form
%   EVENTS (see pseudo_CT_scientific_event_read) through the existing presenter.
%
%   ORIGIN 'stdout': events parsed from the compiled stdout stream. They are
%   presented only while NATIVE_CAPABLE is false (the payload has not written
%   native records, e.g. a payload built before native emission). Each shown
%   stage/status key is remembered in SHOWN.
%   ORIGIN 'native': events from the per-run JSONL file. A native event whose
%   stage/status was already shown from stdout is skipped, so each stage is
%   shown once. Once native records exist they are the source for later stages.
%
%   SHOWN is a containers.Map keyed by 'stage|status' (pass [] to start).
%   PRESENT_ENABLED gates console output only; bookkeeping always happens.
%   Minimum supported MATLAB: R2010b.

if nargin < 2 || isempty(shown)
    shown = containers.Map();
end
present = false(numel(events), 1);
for ii = 1:numel(events)
    key = sprintf('%d|%s', events(ii).stage.index, events(ii).status);
    if strcmp(origin, 'stdout')
        if native_capable
            continue;
        end
        present(ii) = true;
        shown(key) = true;
    else
        if shown.isKey(key)
            continue;
        end
        present(ii) = true;
    end
end
if any(present) && present_enabled
    pseudo_CT_present_scientific_events(events(present), output_context);
end
end
