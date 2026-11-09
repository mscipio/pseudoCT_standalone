function shown = pseudo_CT_scientific_present_once(events, shown, origin, native_capable, output_context, present_enabled)
%PSEUDO_CT_SCIENTIFIC_PRESENT_ONCE Choose one presentation source per stage.
%   SHOWN = PSEUDO_CT_SCIENTIFIC_PRESENT_ONCE(EVENTS, SHOWN, ORIGIN,
%   NATIVE_CAPABLE, OUTPUT_CONTEXT, PRESENT_ENABLED) presents presenter-form
%   EVENTS (see pseudo_CT_scientific_event_read) through the existing presenter.
%
%   ORIGIN 'stdout': events parsed from the compiled stdout stream. An event is
%   presented unless NATIVE_CAPABLE already covers its stage index, so a stage
%   with no native record is still shown from stdout. Each shown stage/status
%   key is remembered in SHOWN.
%   ORIGIN 'native': events from the per-run JSONL file. A native event whose
%   stage/status was already shown from stdout is skipped, so each stage is
%   shown once.
%
%   NATIVE_CAPABLE is either a 1x10 logical vector of stage indices with native
%   coverage (pseudo_CT_scientific_event_read STATE.covered), or a scalar. A
%   scalar true means every stage is covered (legacy callers); a scalar false
%   means none is. Stage-less worker records never count as coverage.
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
        if local_covered(native_capable, events(ii).stage.index)
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

function covered = local_covered(native_capable, index)
% True when native records already cover canonical stage INDEX.
covered = false;
if ~isnumeric(index) && ~islogical(index)
    return;
end
if ~isscalar(index) || index < 1 || index > 10 || index ~= fix(index)
    return;
end
if isscalar(native_capable)
    covered = logical(native_capable);
    return;
end
covered = numel(native_capable) >= index && logical(native_capable(index));
end
