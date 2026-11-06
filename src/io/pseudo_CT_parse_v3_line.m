function [stage, status, kind] = pseudo_CT_parse_v3_line(message)
%PSEUDO_CT_PARSE_V3_LINE Explicit messages from current_compute, not lifecycle.
stage = 0; status = ''; kind = 'explicit';
starts = {'Aligning MPRAGE and creating subject mask.', 5; ...
    'Running SPM New Segment.', 6; 'Registering atlases with DARTEL.', 7; ...
    'Building attenuation map and QC image.', 8};
for ii = 1:size(starts, 1)
    if strcmp(message, starts{ii, 1})
        stage = starts{ii, 2}; status = 'START'; return;
    end
end
dones = {'Alignment and masking completed', 5; 'Segmentation completed', 6; ...
    'Atlas registration completed', 7; 'Attenuation map and QC completed', 8};
for ii = 1:size(dones, 1)
    if ~isempty(regexp(message, ['^' dones{ii, 1} ' \(elapsed [0-9:]+\)\.$'], 'once'))
        stage = dones{ii, 2}; status = 'DONE'; return;
    end
end
if any(strcmp(message, {'Applying inverse warp.'; 'Reslicing atlases into MPRAGE space.'}))
    stage = 7; status = 'INFO';
end
end
