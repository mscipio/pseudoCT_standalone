function layout = pseudo_CT_package_layout()
%PSEUDO_CT_PACKAGE_LAYOUT Identify the source or installed package layout.
%   The nonempty PSEUDOCT_INSTALL_ROOT value is trusted only after its
%   package layout proves whether it is a source checkout or an installed
%   distribution. An empty value means source mode and is anchored to this
%   function's source location. Minimum supported MATLAB: R2010b.

root_from_env = strtrim(getenv('PSEUDOCT_INSTALL_ROOT'));
if isempty(root_from_env)
    config_dir = fileparts(mfilename('fullpath'));
    root = fileparts(fileparts(config_dir));
    if exist(fullfile(root, 'src'), 'dir') ~= 7 || ...
            exist(fullfile(root, 'runtimes'), 'dir') == 7
        error('pseudo_CT:PackageLayout', ...
            'The repository package layout is invalid or ambiguous.');
    end
    layout = struct('mode', 'source', 'root', root);
    return;
end

root = local_strip_sep(root_from_env);
if isempty(root) || root(1) ~= '/'
    error('pseudo_CT:PackageLayout', ...
        'PSEUDOCT_INSTALL_ROOT must be an absolute package root.');
end

has_src = exist(fullfile(root, 'src'), 'dir') == 7;
has_runtimes = exist(fullfile(root, 'runtimes'), 'dir') == 7;
has_launcher = exist(fullfile(root, 'bin', 'pseudoct'), 'file') == 2;
has_manifest = exist(fullfile(root, 'manifest.json'), 'file') == 2;
if has_src && ~has_runtimes
    layout = struct('mode', 'source', 'root', root);
elseif ~has_src && has_runtimes && has_launcher && has_manifest
    layout = struct('mode', 'installed', 'root', root);
else
    error('pseudo_CT:PackageLayout', ...
        'PSEUDOCT_INSTALL_ROOT does not identify a valid source or installed package.');
end
end

function value = local_strip_sep(value)
value = strtrim(value);
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end
