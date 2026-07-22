function ids = pseudo_CT_error_ids()
%PSEUDO_CT_ERROR_IDS Canonical deterministic error identifiers for profile-resource-authority.
%   IDS = PSEUDO_CT_ERROR_IDS() returns a nested struct of error IDs used
%   by the registry, preflight, seams, and tests. Each identifier has the
%   form CATEGORY:SpecificError so callers can catch deterministic causes.
%
%   The ENV_IGNORED family records behavior-changing variables that the
%   manifest owns; seams log the ignored name but do not let it alter
%   execution.
%
%   Minimum supported MATLAB: R2010b.

ids = struct();

ids.PROFILE.InvalidName            = 'PROFILE:InvalidName';
ids.PROFILE.MissingManifestField   = 'PROFILE:MissingManifestField';
ids.PROFILE.InvalidValue           = 'PROFILE:InvalidValue';
ids.PROFILE.R2010bOnly             = 'PROFILE:R2010bOnly';

ids.SPM_ROOT.NotFound              = 'SPM_ROOT:NotFound';

ids.VERS.Incomplete                = 'VERS:Incomplete';
ids.VERS.WrongOrder                = 'VERS:WrongOrder';

ids.ATLAS.AssetMissing             = 'ATLAS:AssetMissing';
ids.ATLAS.IntegrityCheckFailed     = 'ATLAS:IntegrityCheckFailed';

ids.PCA.BackendUnavailable         = 'PCA:BackendUnavailable';

ids.NORMALIZATION.SourceCommandMissing = 'NORMALIZATION:SourceCommandMissing';
ids.NORMALIZATION.ChildLibMissing      = 'NORMALIZATION:ChildLibMissing';
ids.NORMALIZATION.ShellMetachar        = 'NORMALIZATION:ShellMetachar';

ids.PROVENANCE.ChecksumMismatch    = 'PROVENANCE:ChecksumMismatch';
ids.PROVENANCE.RecordMissing       = 'PROVENANCE:RecordMissing';
ids.PROVENANCE.InventoryMissing    = 'PROVENANCE:InventoryMissing';

ids.RELEASE.ValidationIncomplete   = 'RELEASE:ValidationIncomplete';
ids.RELEASE.OwnerAcceptanceMissing = 'RELEASE:OwnerAcceptanceMissing';

ids.ALIAS.InvalidOverride          = 'ALIAS:InvalidOverride';

ids.BONE.CleanupFixed              = 'BONE:CleanupFixed';

ids.ENV_IGNORED.ZERO_BACKGROUND    = 'ENV_IGNORED:PSEUDOCT_ZERO_BACKGROUND';
ids.ENV_IGNORED.USE_PRINCOMP       = 'ENV_IGNORED:PSEUDOCT_USE_PRINCOMP';
ids.ENV_IGNORED.SPM_ROOT           = 'ENV_IGNORED:PSEUDOCT_SPM_ROOT';
ids.ENV_IGNORED.SPM_VARIANT        = 'ENV_IGNORED:PSEUDOCT_SPM_VARIANT';
ids.ENV_IGNORED.BATCH_ATLAS        = 'ENV_IGNORED:PSEUDOCT_BATCH_ATLAS';
ids.ENV_IGNORED.KEEP_TMP           = 'ENV_IGNORED:PSEUDOCT_KEEP_TMP';
ids.ENV_IGNORED.FS_LIBSTDCPP_ROOT  = 'ENV_IGNORED:PSEUDOCT_FS_LIBSTDCPP_ROOT';

end
