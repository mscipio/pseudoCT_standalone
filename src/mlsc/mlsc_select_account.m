function account = mlsc_select_account(accounts)
%MLSC_SELECT_ACCOUNT Select one runtime-only Slurm account.
%   ACCOUNT = MLSC_SELECT_ACCOUNT(ACCOUNTS) returns the only account without
%   prompting, opens a MATLAB single-selection dialog for multiple accounts,
%   and returns an empty string when the dialog is cancelled. No account is
%   stored by this function.
%
%   Minimum supported MATLAB: R2010b.

if nargin ~= 1 || ~iscell(accounts)
    error('pseudo_CT:MLSCAccountsRequired', ...
        'A cell array of available MLSC Slurm accounts is required.');
end

accounts = local_unique_accounts(accounts);
if isempty(accounts)
    error('pseudo_CT:MLSCNoAccounts', ...
        'No Slurm account is available for the authenticated MLSC user.');
end
if isscalar(accounts)
    account = accounts{1};
    return;
end

[selection, accepted] = listdlg('PromptString', 'Select an MLSC Slurm account:', ...
    'SelectionMode', 'single', 'ListString', accounts, ...
    'Name', 'MLSC Slurm account');
if ~accepted || isempty(selection)
    account = '';
else
    account = accounts{selection(1)};
end
end

function accounts = local_unique_accounts(values)
accounts = {};
for ii = 1:length(values)
    if ~ischar(values{ii})
        continue;
    end
    candidate = strtrim(values{ii});
    if isempty(candidate) || local_account_seen(accounts, candidate)
        continue;
    end
    accounts{end + 1} = candidate; %#ok<AGROW>
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
