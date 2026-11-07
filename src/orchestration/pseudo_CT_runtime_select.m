function out = pseudo_CT_runtime_select(config, label)
%PSEUDO_CT_RUNTIME_SELECT Installed MATLAB Runtime release selection.
%   RELEASES = PSEUDO_CT_RUNTIME_SELECT() returns the installed releases in
%   catalog order as a struct array (fields label, mcr_version, default), read
%   from 'bin/pseudoct --list-releases' under PSEUDOCT_INSTALL_ROOT. The
%   result is empty in source/repository mode.
%
%   CONFIG = PSEUDO_CT_RUNTIME_SELECT(CONFIG, LABEL) binds one installed
%   release to a loaded profile config. Source/licensed mode (empty
%   PSEUDOCT_INSTALL_ROOT) returns CONFIG unchanged. In installed mode an
%   empty LABEL falls back to PSEUDOCT_RUNTIME_RELEASE and then to the catalog
%   default. The launcher is the only runtime-selection mechanism:
%   'bin/pseudoct resolve --mcr LABEL' prints PSEUDOCT_RUNTIME/MCR_ROOT/RUNNER
%   assignments and fails when the release is absent or its MCR mismatches.
%   On success this sets config.current.runner, config.current.mcr_root and
%   config.current.release (LABEL), plus config.current.build_manifest and
%   resource_manifest under <install>/runtimes/LABEL/payload, and exports PSEUDOCT_RUNTIME_RELEASE,
%   PSEUDOCT_RUNTIME_MCR_ROOT and PSEUDOCT_RUNTIME_MCR_VERSION for the MLSC
%   identity check. Any failure is raised before scientific processing.
%
%   Minimum supported MATLAB: R2010b.

layout = pseudo_CT_package_layout();
if nargin == 0
    if strcmp(layout.mode, 'source')
        out = struct('label', {}, 'mcr_version', {}, 'default', {});
    else
        out = local_installed_releases(layout.root);
    end
    return;
end
out = config;
if strcmp(layout.mode, 'source')
    return;
end
install_root = layout.root;
releases = local_installed_releases(install_root);
if nargin < 2 || isempty(label)
    label = strtrim(getenv('PSEUDOCT_RUNTIME_RELEASE'));
end
if isempty(label)
    label = local_default_label(releases);
end
if isempty(regexp(label, '^[A-Za-z0-9]+$', 'once'))
    error('pseudo_CT:RuntimeSelection', ...
        'No valid MATLAB Runtime release is selected.');
end
index = find(strcmp({releases.label}, label), 1);
if isempty(index)
    error('pseudo_CT:RuntimeSelection', ...
        'MATLAB Runtime %s is not installed.', label);
end

inherited_release = strtrim(getenv('PSEUDOCT_RUNTIME_RELEASE'));
inherited_mcr_root = strtrim(getenv('PSEUDOCT_RUNTIME_MCR_ROOT'));
command = ['cd ' local_shell_quote(install_root) ...
    ' && bin/pseudoct resolve --mcr ' label];
if strcmp(label, inherited_release) && ~isempty(inherited_mcr_root)
    command = [command ' --mcr-root ' local_shell_quote(inherited_mcr_root)];
end
[status, text] = system(command);
if status ~= 0
    error('pseudo_CT:RuntimeSelection', ...
        ['MATLAB Runtime %s is unavailable or does not match its ' ...
        'release; run bin/pseudoct --list-releases.'], label);
end
runner = local_assignment(text, 'PSEUDOCT_RUNNER');
mcr_root = local_assignment(text, 'PSEUDOCT_MCR_ROOT');
if isempty(runner) || isempty(mcr_root) || ...
        exist(runner, 'file') ~= 2 || exist(mcr_root, 'dir') ~= 7
    error('pseudo_CT:RuntimeSelection', ...
        'MATLAB Runtime %s resolution is incomplete.', label);
end

out.current.runner = runner;
out.current.mcr_root = mcr_root;
out.current.release = label;
% Per-release manifests written at assembly by 'package-manifests'.
payload_dir = fullfile(install_root, 'runtimes', label, 'payload');
out.current.build_manifest = fullfile(payload_dir, 'build_manifest.mat');
out.current.resource_manifest = fullfile(payload_dir, ...
    'resource_manifest.mat');
setenv('PSEUDOCT_RUNTIME_RELEASE', label);
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', mcr_root);
setenv('PSEUDOCT_RUNTIME_MCR_VERSION', releases(index).mcr_version);
end

function releases = local_installed_releases(install_root)
releases = struct('label', {}, 'mcr_version', {}, 'default', {});
[status, text] = system(['cd ' local_shell_quote(install_root) ...
    ' && bin/pseudoct --list-releases']);
if status ~= 0
    error('pseudo_CT:RuntimeSelection', ...
        'The installed MATLAB Runtime catalog is unavailable.');
end
lines = regexp(text, char(10), 'split');
for ii = 1:length(lines)
    line = strrep(lines{ii}, char(13), '');
    if isempty(strtrim(line))
        continue;
    end
    fields = regexp(line, char(9), 'split');
    if length(fields) ~= 3
        error('pseudo_CT:RuntimeSelection', ...
            'The installed MATLAB Runtime catalog is malformed.');
    end
    label = strtrim(fields{1});
    mcr_version = strtrim(fields{2});
    if isempty(regexp(label, '^[A-Za-z0-9]+$', 'once')) || ...
            isempty(regexp(mcr_version, '^[0-9]+\.[0-9]+$', 'once'))
        error('pseudo_CT:RuntimeSelection', ...
            'The installed MATLAB Runtime catalog is malformed.');
    end
    releases(end + 1) = struct('label', label, ...
        'mcr_version', mcr_version, ...
        'default', strcmp(strtrim(fields{3}), 'default')); %#ok<AGROW>
end
end

function label = local_default_label(releases)
label = '';
for ii = 1:length(releases)
    if releases(ii).default
        label = releases(ii).label;
        return;
    end
end
error('pseudo_CT:RuntimeSelection', ...
    'No default MATLAB Runtime release is installed.');
end

function value = local_assignment(text, name)
%LOCAL_ASSIGNMENT Value of one NAME='value' line from resolve output.
value = '';
if ~(strcmp(name, 'PSEUDOCT_RUNNER') || strcmp(name, 'PSEUDOCT_MCR_ROOT'))
    return;
end
quote = char(39);
prefix = [name '=' quote];
lines = regexp(text, char(10), 'split');
for ii = 1:length(lines)
    line = lines{ii};
    if length(line) > length(prefix) && ...
            strncmp(line, prefix, length(prefix)) && line(end) == quote
        encoded = line(length(prefix) + 1:end - 1);
        [value, valid] = local_decode_assignment(encoded, quote);
        if ~valid
            value = '';
        end
        return;
    end
end
end

function [value, valid] = local_decode_assignment(encoded, quote)
%LOCAL_DECODE_ASSIGNMENT Decode only the POSIX single-quote escape.
value = '';
valid = true;
slash = char(92);
ii = 1;
while ii <= length(encoded)
    character = encoded(ii);
    code = double(character);
    if code < 32 || code == 127
        valid = false;
        return;
    elseif character == quote
        if ii + 3 > length(encoded) || encoded(ii + 1) ~= slash || ...
                encoded(ii + 2) ~= quote || encoded(ii + 3) ~= quote
            valid = false;
            return;
        end
        value(end + 1) = quote; %#ok<AGROW>
        ii = ii + 4;
    elseif character == slash
        valid = false;
        return;
    else
        value(end + 1) = character; %#ok<AGROW>
        ii = ii + 1;
    end
end
end

function quoted = local_shell_quote(value)
%LOCAL_SHELL_QUOTE POSIX single-quote a path for system().
quote = char(39);
quoted = [quote strrep(value, quote, [quote char(92) quote quote]) quote];
end
