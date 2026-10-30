function accounts = mlsc_parse_slurm_accounts(response)
%MLSC_PARSE_SLURM_ACCOUNTS Parse and deduplicate authenticated Slurm accounts.
%   ACCOUNTS = MLSC_PARSE_SLURM_ACCOUNTS(RESPONSE) accepts the cell-array or
%   text response from `sshare -U -u $USER -P --format=Account --noheader`,
%   whose canonical lines carry a single Account field (with an optional
%   trailing column pipe), as well as legacy multi-column output where the
%   Account is the first whitespace field. Blank, header, separator, and
%   malformed lines are ignored. Account names are returned in first-seen
%   order.
%
%   Minimum supported MATLAB: R2010b.

accounts = {};
lines = local_response_lines(response);
for ii = 1:length(lines)
    line = strtrim(lines{ii});
    if isempty(line)
        continue;
    end

    fields = regexp(line, '\s+', 'split');
    candidate = strtrim(fields{1});
    % Canonical single-field output may end in a trailing column pipe; it
    % is not part of the account name.
    candidate = regexprep(candidate, '\|$', '');
    if isempty(candidate) || strcmpi(candidate, 'account') || ...
            isempty(regexp(candidate, '^[A-Za-z0-9][A-Za-z0-9_.@/-]*$', 'once'))
        continue;
    end
    if ~local_account_seen(accounts, candidate)
        accounts{end + 1} = candidate; %#ok<AGROW>
    end
end
end

function lines = local_response_lines(response)
if ischar(response)
    if size(response, 1) > 1
        lines = cellstr(response);
    else
        lines = regexp(response, '\r\n|\n|\r', 'split');
    end
elseif iscell(response)
    lines = {};
    for ii = 1:length(response)
        if ischar(response{ii})
            if size(response{ii}, 1) > 1
                split_lines = cellstr(response{ii});
            else
                split_lines = regexp(response{ii}, '\r\n|\n|\r', 'split');
            end
            lines = [lines split_lines]; %#ok<AGROW>
        end
    end
else
    error('pseudo_CT:MLSCAccountResponse', ...
        'The MLSC Slurm account response must be text or a cell array of text.');
end
end

function seen = local_account_seen(accounts, candidate)
seen = false;
for ii = 1:length(accounts)
    if strcmp(accounts{ii}, candidate)
        seen = true;
        return;
    end
end
end
