function test_pseudoct_direct_scientific_streams(scratch_dir)
% Focused read-only parser smoke. Caller allocates scratch; no science runs.
assert(nargin == 1 && ~isempty(strfind(scratch_dir, [filesep '.aria' filesep 'scratch' filesep])));
texts = {sprintf(['Opening file: mprage.nii and calculating the mask ...\n' ...
    'Starting the New Segment process (be patient!!) ...\nRunning ''New Segment''\n']); ...
    sprintf(['Aligning MPRAGE and creating subject mask.\n' ...
    'Alignment and masking completed (elapsed 00:00:01).\n' ...
    'Running SPM New Segment.\nRegistering atlases with DARTEL.\n' ...
    'Applying inverse warp.\nReslicing atlases into MPRAGE space.\n' ...
    'Atlas registration completed (elapsed 00:00:01).\n' ...
    'Building attenuation map and QC image.\n' ...
    'Attenuation map and QC completed (elapsed 00:00:01).'])};
versions = {'v2'; 'v3'};
schemas = cell(1, 2);
for k = 1:2
    path = fullfile(scratch_dir, ['parser-' versions{k} '.log']);
    f = fopen(path, 'wb'); fwrite(f, texts{k}); fclose(f);
    expected = pseudo_CT_replay_scientific_stream(path, versions{k}, 'test');
    schemas{k} = fieldnames(expected);
    split = floor(length(texts{k}) / 2); % deliberately mid-line
    while texts{k}(split) == char(10), split = split + 1; end
    f = fopen(path, 'wb'); fwrite(f, texts{k}(1:split)); fclose(f);
    [a, state] = pseudo_CT_scientific_stream(path, versions{k}, 'test', [], false);
    [none, state] = pseudo_CT_scientific_stream(path, versions{k}, 'test', state, false);
    assert(isempty(none) && ~isempty(state.reader.buffer));
    f = fopen(path, 'ab'); fwrite(f, texts{k}(split+1:end)); fclose(f);
    [b, state] = pseudo_CT_scientific_stream(path, versions{k}, 'test', state, false);
    [c, state] = pseudo_CT_scientific_stream(path, versions{k}, 'test', state, true);
    [none, state] = pseudo_CT_scientific_stream(path, versions{k}, 'test', state, true);
    assert(isempty(none));
    actual = [a; b; c];
    % Observation timestamps legitimately differ between polls.
    assert(isequal({actual.message}, {expected.message}));
    assert(isequal({actual.status}, {expected.status}));
    assert(isequal([actual.stage], [expected.stage]));
    if k == 1
        assert(isequal([actual.stage], [expected.stage]));
        assert(~any(strcmp({actual.status}, 'DONE')));
        assert(sum(strcmp({actual.status}, 'START')) == 2);
        pseudo_CT_output_console_visible('RESET');
        pseudo_CT_present_scientific_events(actual, struct('live', false, 'console_profile', 'local-legacy'));
        records = pseudo_CT_output_console_visible('DRAIN_EVENTS');
        assert(~any(strcmp({records.status}, 'DONE')));
    end
    fprintf('PASS %s split=%d events=%d unchanged/final polls=0 duplicates=0\n', versions{k}, split, length(actual));
end
assert(isequal(schemas{1}, schemas{2}));
% The operational phase-start message must not preempt scientific evidence.
pseudo_CT_output_console_visible('RESET');
context = struct('console_profile', 'local-legacy', 'direct_scientific_stream', true, ...
    'subject_index', 1, 'source', 'orchestrator');
pseudo_CT_output_console_visible('INFO', 'Legacy pseudo-CT started.', context);
records = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(~isempty(records) && all(strcmp({records.status}, 'INFO')));
assert(~any([records.stage_number] == 5));
fprintf('PASS identical v2/v3 event fields and canonical stages\n');
end
