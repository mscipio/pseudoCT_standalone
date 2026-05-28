function [ute_fn, umap_fn] = pseudo_CT_auto_discover_ute_umap(mprage_fn)

ute_fn = 0;
umap_fn = 0;

[patha, ~, ~] = fileparts(deblank(mprage_fn));

ss = strfind(patha, strcat(filesep, 'MR', filesep));
if length(ss) > 0
    dir_b = patha(1:(ss + 3));

    listi = dir(strcat(dir_b, 'UTE_2', filesep, '*0001.*'));
    if length(listi) == 1
        ute_fn = fullfile(dir_b, 'UTE_2', listi(1).name);
    elseif length(listi) > 1
        ute_fn = fullfile(dir_b, 'UTE_2', listi(1).name);
    end

    listi = dir(strcat(dir_b, 'UMAP', filesep, '*0001.*'));
    if length(listi) == 1
        umap_fn = fullfile(dir_b, 'UMAP', listi(1).name);
    elseif length(listi) > 1
        umap_fn = fullfile(dir_b, 'UMAP', listi(1).name);
    else
        aa = ls(fullfile(dir_b, '*UMAP*'));
        if size(aa, 1) ~= 0
            listi = dir(fullfile(dir_b, deblank(aa(1, :)), '*0001.*'));
        else
            listi = [];
        end
        if length(listi) == 1
            umap_fn = fullfile(dir_b, deblank(aa(1, :)), listi(1).name);
        elseif length(listi) > 1
            umap_fn = fullfile(dir_b, deblank(aa(1, :)), listi(1).name);
        end
    end
end

return