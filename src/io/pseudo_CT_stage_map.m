function [stage_map, public_stage, public_total, stage_title, public_span] = ...
        pseudo_CT_stage_map(policy, producer_stage, producer_total)
%PSEUDO_CT_STAGE_MAP Return the public stage map for one profile policy.
%   STAGE_MAP = PSEUDO_CT_STAGE_MAP(CONFIG) accepts a profile config or a
%   compact policy struct with mode, output_policy, and reference_policy
%   fields. The map is keyed by those three policy values.
%   [STAGE_MAP, NUMBER, TOTAL, TITLE, SPAN] = PSEUDO_CT_STAGE_MAP(STAGE_MAP, N, M)
%   translates one producer stage into its public number and total, or returns
%   a declared multi-stage public span when one producer operation covers a
%   composite workflow range. A policy
%   that does not match a shipped profile raises pseudo_CT:StageMap:UnknownPolicy
%   (fail closed; no producer numbering is inferred). An empty policy returns an
%   empty map. An undeclared producer stage returns NUMBER=0.
%
%   Public workflow numbering is fixed at ten logical stages for every
%   supported profile. Producer stages are mapped only when they correspond to
%   a logical workflow stage or a declared composite span; scheduler, retrieval,
%   promotion-only and cleanup events remain unnumbered otherwise.
%   PRODUCER_TOTAL is retained as producer provenance, never as the public
%   total.

stage_map = local_empty_map();
public_stage = 0;
public_total = 0;
stage_title = '';
public_span = [];

if local_is_map(policy)
    stage_map = policy;
elseif ~isempty(policy)
    % Fail closed: a policy that does not resolve to a shipped map must not
    % fall back to producer numbering. Callers that have no policy at all
    % pass [] and keep their documented no-map behavior.
    [mode, output_policy, reference_policy] = ...
        local_policy_values(policy);
    maps = local_maps();
    found = false;
    for ii = 1:length(maps)
        candidate = maps(ii);
        if ~isempty(mode) && strcmp(mode, candidate.mode) && ...
                strcmp(output_policy, candidate.output_policy) && ...
                strcmp(reference_policy, candidate.reference_policy)
            stage_map = candidate;
            found = true;
            break;
        end
    end
    if ~found
        error('pseudo_CT:StageMap:UnknownPolicy', ...
            ['Stage map policy does not match a shipped profile: ' ...
            'mode=%s output=%s reference=%s'], ...
            local_text(mode), ...
            local_text(output_policy), local_text(reference_policy));
    end
end

if nargin < 2 || ~local_is_map(stage_map) || ...
        ~isnumeric(producer_stage) || ~isscalar(producer_stage) || ...
        ~isfinite(producer_stage) || producer_stage < 1 || ...
        producer_stage ~= floor(producer_stage)
    return;
end
if nargin < 3 || isempty(producer_total)
    producer_total = stage_map.producer_total;
end
if ~isnumeric(producer_total) || ~isscalar(producer_total) || ...
        ~isfinite(producer_total) || producer_total < 1 || ...
        producer_total ~= floor(producer_total)
    return;
end

if producer_total == stage_map.producer_total
    slot = find(stage_map.producer_stage_numbers == producer_stage, 1);
    if ~isempty(slot)
        public_stage = stage_map.public_stage_numbers(slot);
        public_total = stage_map.total;
        stage_title = stage_map.titles{slot};
        return;
    end
    if isfield(stage_map, 'producer_span_numbers') && ...
            isfield(stage_map, 'public_stage_spans')
        slot = find(stage_map.producer_span_numbers == producer_stage, 1);
        if ~isempty(slot)
            candidate_span = stage_map.public_stage_spans{slot};
            if isnumeric(candidate_span) && numel(candidate_span) == 2 && ...
                    all(isfinite(candidate_span(:))) && ...
                    all(candidate_span(:) == floor(candidate_span(:))) && ...
                    candidate_span(1) >= 1 && candidate_span(2) <= stage_map.total && ...
                    candidate_span(2) >= candidate_span(1)
                public_span = reshape(candidate_span, 1, 2);
                public_total = stage_map.total;
                stage_title = sprintf('Composite producer stages %d-%d', ...
                    public_span(1), public_span(2));
            end
        end
    end
    if ~isempty(public_span)
        return;
    end
end
% The output emitter may receive a stage already normalized by an upstream
% stage-context helper. Accept only a declared public stage in that case.
if producer_total == stage_map.total
    slot = find(stage_map.public_stage_numbers == producer_stage, 1);
    if ~isempty(slot)
        public_stage = producer_stage;
        public_total = stage_map.total;
        stage_title = stage_map.titles{slot};
    end
end
end

function [mode, output_policy, reference_policy] = ...
        local_policy_values(policy)
mode = '';
output_policy = '';
reference_policy = '';
if ~isstruct(policy) || ~isscalar(policy)
    return;
end
try
    mode = policy.mode;
    if isfield(policy, 'io_policy') && isstruct(policy.io_policy)
        output_policy = policy.io_policy.output;
        reference_policy = policy.io_policy.reference;
    else
        output_policy = policy.output_policy;
        reference_policy = policy.reference_policy;
    end
catch %#ok<CTCH>
    mode = '';
    output_policy = '';
    reference_policy = '';
end
if ~(ischar(mode) && ischar(output_policy) && ischar(reference_policy))
    mode = '';
    output_policy = '';
    reference_policy = '';
end
end

function text = local_text(value)
if ischar(value) && ~isempty(value)
    text = value;
else
    text = '<missing>';
end
end

function yes = local_is_map(value)
yes = isstruct(value) && isscalar(value) && ...
    isfield(value, 'producer_total') && isfield(value, 'total') && ...
    isfield(value, 'producer_stage_numbers') && ...
    isfield(value, 'public_stage_numbers') && isfield(value, 'titles') && ...
    isfield(value, 'mode') && ...
    isfield(value, 'output_policy') && isfield(value, 'reference_policy');
end

function map = local_empty_map()
map = struct('profile', '', 'mode', '', ...
    'output_policy', '', 'reference_policy', '', 'producer_total', 0, ...
    'total', 0, 'producer_stage_numbers', [], ...
    'public_stage_numbers', [], 'producer_span_numbers', [], ...
    'public_stage_spans', {{}}, 'titles', {{}}, 'stage_ids', {{}});
end

function maps = local_maps()
% Producer citations (all paths under src/):
%  - local (10 stages): stage 1 and
%    promotion in orchestration/pseudo_CT_run_lifecycle.m (local_run_subject);
%    stages 2-8 in backends/local/pseudo_CT_run_local_current_subject.m.
%  - local-mprage-only: same producers as local, DICOM omitted.
%  - mlsc and mlsc-mprage-only: stages 1-2 and 5-8 in
%    orchestration/pseudo_CT_run_lifecycle.m (local_finalize_remote_subject
%    for 5-8); stages 3-4 in backends/mlsc/mlsc_lifecycle.m.
% No totals or starts are inferred from these maps beyond the policy keys.
maps = repmat(local_empty_map(), 1, 4);
maps(1) = local_make_map('local', 'local', ...
    'nifti-and-dicom', 'umap-required', 10, 10, 1:10, 1:10, ...
    {'Input MPRAGE preparation'; 'MPRAGE recentering'; ...
     'Aliasing correction'; 'FreeSurfer MPRAGE normalization'; ...
     'MPRAGE alignment and masking'; 'SPM New Segment'; ...
     'DARTEL atlas registration'; 'Attenuation-map and QC generation'; ...
     'Writing DICOM output'; 'Output promotion and cleanup'});
maps(2) = local_make_map('local-mprage-only', 'local', ...
    'nifti-only', 'none', 9, 10, 1:8, 1:8, ...
    {'Input MPRAGE preparation'; 'MPRAGE recentering'; ...
     'Aliasing correction'; 'FreeSurfer MPRAGE normalization'; ...
     'MPRAGE alignment and masking'; 'SPM New Segment'; ...
     'DARTEL atlas registration'; 'Attenuation-map and QC generation'});
maps(3) = local_make_map('mlsc', 'mlsc', ...
    'nifti-and-dicom', 'umap-required', 8, 10, [1 6 7], [1 9 10], ...
    {'Input MPRAGE preparation'; 'Writing DICOM output'; ...
     'Output promotion'});
maps(4) = local_make_map('mlsc-mprage-only', 'mlsc', ...
    'nifti-only', 'none', 8, 10, 1, 1, ...
    {'Input MPRAGE preparation'});
% Stable public workflow IDs. Producer maps omit non-workflow scheduler,
% retrieval, and housekeeping stages; every numbered event uses total 10.
workflow_ids = {'workflow.input_prepare'; 'workflow.recenter'; ...
    'workflow.alias_correct'; 'workflow.normalize'; ...
    'workflow.align_mask'; 'workflow.segment'; 'workflow.dartel'; ...
    'workflow.attenuation_qc'; 'workflow.dicom_output'; ...
    'workflow.full_output_finalize'};
workflow_titles = {'Input MPRAGE preparation'; 'MPRAGE recentering'; ...
    'Aliasing correction'; 'FreeSurfer MPRAGE normalization'; ...
    'MPRAGE alignment and masking'; 'SPM New Segment'; ...
    'DARTEL atlas registration'; 'Attenuation-map and QC generation'; ...
    'Writing DICOM output'; 'Full-mode output promotion'};
for ii = 1:length(maps)
    ids = cell(1, length(maps(ii).public_stage_numbers));
    titles = cell(1, length(maps(ii).public_stage_numbers));
    for jj = 1:length(ids)
        public_number = maps(ii).public_stage_numbers(jj);
        ids{jj} = workflow_ids{public_number};
        titles{jj} = workflow_titles{public_number};
    end
    maps(ii).stage_ids = ids;
    maps(ii).titles = titles;
end
end

function map = local_make_map(profile, mode, output_policy, ...
        reference_policy, producer_total, total, producer_stages, ...
        public_stages, titles)
map = local_empty_map();
map.profile = profile;
map.mode = mode;
map.output_policy = output_policy;
map.reference_policy = reference_policy;
map.producer_total = producer_total;
map.total = total;
map.producer_stage_numbers = producer_stages;
map.public_stage_numbers = public_stages;
map.titles = titles;
end
