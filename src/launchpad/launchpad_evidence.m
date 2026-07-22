function snapshot = launchpad_evidence(event, previous, values)
%LAUNCHPAD_EVIDENCE Capture a bounded, deterministic Launchpad lifecycle.
%   This seam records state only; it does not submit, poll, retrieve, or
%   clean remote work. The existing SSH/PBS lifecycle remains authoritative.

if nargin < 1 || isempty(event)
    event = 'init';
end
if nargin < 2 || isempty(previous)
    previous = struct();
end
if nargin < 3 || isempty(values)
    values = struct();
end

if strcmp(event, 'write')
    evidence_dir = previous;
    snapshot = values;
    if exist(evidence_dir, 'dir') ~= 7
        error('LAUNCHPAD:EVIDENCE_PATH', 'Evidence directory not found: %s', evidence_dir);
    end
    save(fullfile(evidence_dir, 'launchpad_evidence.mat'), 'snapshot');
    return;
end

if strcmp(event, 'init')
    snapshot = new_snapshot(previous);
else
    snapshot = previous;
    if ~isfield(snapshot, 'schema')
        snapshot = new_snapshot(snapshot);
    end
    if ~isfield(snapshot, 'lifecycle') || isempty(snapshot.lifecycle)
        snapshot.lifecycle = {'init'};
    end
    snapshot.lifecycle{end + 1} = event;
    snapshot = merge_values(snapshot, values);
end
end

function snapshot = new_snapshot(values)
snapshot = struct();
snapshot.schema = 'pseudo-CT.launchpad-evidence/v1';
snapshot.profile = 'launchpad';
snapshot.lifecycle = {'init'};
snapshot.subject_count = 0;
snapshot.jobname = '';
snapshot.jobnum = 0;
snapshot.exit_status = [];
snapshot.pbs_logs = {};
snapshot.att_map_present = false;
snapshot.cleanup = '';
snapshot = merge_values(snapshot, values);
end

function snapshot = merge_values(snapshot, values)
if ~isstruct(values)
    return;
end
names = fieldnames(values);
for ii = 1:length(names)
    snapshot.(names{ii}) = values.(names{ii});
end
end
