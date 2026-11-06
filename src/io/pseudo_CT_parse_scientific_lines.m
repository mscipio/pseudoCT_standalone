function [events, state] = pseudo_CT_parse_scientific_lines(lines, path, version, subject, state)
%PSEUDO_CT_PARSE_SCIENTIFIC_LINES Direct compiled lines -> shared events.
% Each event: subject; stage (index/title/total); status; message; source
% (version/file); source_timestamp ('' when unavailable); observation_timestamp;
% transition_kind ('explicit' or 'inferred'). No filesystem writes or science.
if ~any(strcmp(version, {'v2'; 'v3'}))
    error('pseudo_CT:StreamVersion', 'Specify v2 or v3 explicitly.');
end
if nargin < 5 || isempty(state)
    state = struct('active_stage', 0, 'version', version, ...
        'subject', subject, 'started', false(1, 10));
end
if ~strcmp(state.version, version) || ~strcmp(state.subject, subject)
    error('pseudo_CT:StreamIdentity', 'A parser cannot switch version or subject.');
end
template = struct('subject', subject, 'stage', struct('index', 0, 'title', '', 'total', 10), ...
    'status', '', 'message', '', 'source', struct('version', version, 'file', path), ...
    'source_timestamp', '', 'observation_timestamp', '', 'transition_kind', 'explicit');
events = repmat(template, 0, 1);
for ii = 1:length(lines)
    [body, stamp, level] = local_body(lines{ii});
    if strcmp(version, 'v2')
        [n, status, kind] = pseudo_CT_parse_v2_line(body);
    else
        [n, status, kind] = pseudo_CT_parse_v3_line(body);
    end
    % Severity takes precedence over milestone-like text in warnings/errors.
    if strcmp(level, 'WARN') || ~isempty(regexp(body, '^[{ ]*[Ww]arning\s*:', 'once'))
        n = state.active_stage; status = 'WARN'; kind = 'explicit';
    elseif strcmp(level, 'ERROR') || ~isempty(regexp(body, '^(Error|ERROR|\?\?\? Error)', 'once'))
        n = state.active_stage; status = 'ERROR'; kind = 'explicit';
    end
    if isempty(status), continue; end
    if strcmp(status, 'START')
        if state.started(n) && state.active_stage == n
            status = 'INFO'; % second explicit running marker, not a new start
        end
        state.started(n) = true;
    end
    if n > 0, state.active_stage = n; end
    event = template;
    event.stage.index = n;
    if n > 0
        policy = struct('mode', 'local', 'implementation', 'current', ...
            'output_policy', 'nifti-and-dicom', 'reference_policy', 'umap-required');
        [~, ~, ~, event.stage.title] = pseudo_CT_stage_map(policy, n, 10);
    end
    event.status = status;
    event.message = local_redact(body);
    event.source_timestamp = stamp;
    event.observation_timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    event.transition_kind = kind;
    events(end + 1, 1) = event; %#ok<AGROW>
end
end

function [body, stamp, level] = local_body(line)
body = strtrim(line(line ~= char(8))); stamp = ''; level = '';
tokens = regexp(body, '^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\]\s+(INFO|SUCCESS|WARN|ERROR)\s+(.*)$', 'tokens', 'once');
if ~isempty(tokens)
    stamp = tokens{1}; level = tokens{2}; body = tokens{3};
    body = regexprep(body, '^(\[(stage \d+/\d+|subject[^\]]*)\]\s*)+', '');
end
body = strtrim(body);
end

function text = local_redact(text)
% Raw legacy source stays untouched; never expose credential values in events.
text = regexprep(text, ['(?i)(username|user|password|passphrase|account|token|secret)' ...
    '([ \t]*[:=][ \t]*|[ \t]+)[^ \t,;]+'], '$1$2<redacted>');
end
