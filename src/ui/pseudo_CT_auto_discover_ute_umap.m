function [ute_fn, umap_fn] = pseudo_CT_auto_discover_ute_umap(mprage_fn)
% PSEUDO_CT_AUTO_DISCOVER_UTE_UMAP  Auto-discover UTE/UMAP for batch execution.
%   [UTE_FN, UMAP_FN] = PSEUDO_CT_AUTO_DISCOVER_UTE_UMAP(MPRAGE_FN) wraps
%   the shared pseudo_CT_discover_ute_umap helper.  Identical call signature
%   to the original function; all sibling-folder logic is in the shared helper.
%
%   See also pseudo_CT_discover_ute_umap.

[ute_fn, umap_fn] = pseudo_CT_discover_ute_umap(mprage_fn);

return
