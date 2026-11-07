function args = pseudo_CT_lifecycle_arguments(varargin)
%PSEUDO_CT_LIFECYCLE_ARGUMENTS Named-argument contract of pseudo_CT_run_lifecycle.
%   ARGS = PSEUDO_CT_LIFECYCLE_ARGUMENTS(NAME, VALUE, ...) parses the lifecycle
%   parameters. This one definition is shared by the source named-argument path
%   and the deployed path (parse_deployed_arguments), so both accept the same
%   names with the same validation. Unknown names raise
%   MATLAB:InputParser:UnmatchedParameter.
%   Minimum supported MATLAB: R2010b.

p = inputParser;
p.addParamValue('profile', '', @(x) ischar(x));
p.addParamValue('subjects', '', @(x) ischar(x) || iscell(x));
p.addParamValue('umap_files', [], @(x) isempty(x) || ischar(x) || iscell(x));
p.addParamValue('resolved_jobs', struct([]), @(x) isstruct(x));
p.addParamValue('correct_aliasing', [], ...
    @(x) isempty(x) || ((isnumeric(x) || islogical(x)) && ...
    isscalar(x) && ismember(double(x), [0 1])));
p.addParamValue('recenter_before_normalization', [], ...
    @(x) isempty(x) || ((isnumeric(x) || islogical(x)) && ...
    isscalar(x) && ismember(double(x), [0 1])));
% Optional runtime retention override for profile comparison. Omitted
% keeps the profile default; an explicit 0/1 (or scalar logical)
% overrides config.cleanup_on_success after the profile load.
p.addParamValue('cleanup_on_success', [], ...
    @(x) isempty(x) || (islogical(x) && isscalar(x)) || ...
    (isnumeric(x) && isscalar(x) && ismember(x, [0 1])));
% Optional, out-of-band MLSC trusted host-key material/provider.  Accepts a
% character known_hosts record or a zero-argument function handle returning
% one; it is never read from a profile and never logged.  Empty (default)
% selects the password-authentication workflow; a supplied
% value selects strict pinned host-key verification.
p.addParamValue('mlsc_host_key_provider', [], ...
    @(x) isempty(x) || ischar(x) || isa(x, 'function_handle'));
% Explicit operator-selected current-MLSC artifact-root override.
p.addParamValue('mlsc_current_artifact_root', '', @(x) ischar(x));
p.addParamValue('headless_mode', false, ...
    @(x) islogical(x) && isscalar(x));
p.addParamValue('headless_credentials', struct(), ...
    @(x) isstruct(x) && numel(x) == 1);
p.addParamValue('group_account', '', @(x) ischar(x));
p.parse(varargin{:});
args = p.Results;
end
