function out=pseudo_CT_overlay2(img1, img2, pct, colour, map)
%PSEUDO_CT_OVERLAY2 Overlay one image in colour on another image.
%   OUT = PSEUDO_CT_OVERLAY2(IMG1, IMG2, PCT, COLOUR, MAP)
%   Scales IMG1 to its maximum and returns an RGB image in which IMG2 is
%   overlaid with transparency PCT. IMG2 is used as given, so callers scale it
%   (the QC callers divide by its maximum). When MAP has more than one element,
%   IMG2 is indexed into MAP and shown in colour; otherwise IMG2 is blended in
%   the 1-by-3 RGB COLOUR.
%   The file was previously toverlay2.m (function toverlay); the name now matches
%   the function. Origin: Steve Sawiak, 2006. Minimum supported MATLAB: R2010b.

out = zeros(size(img1,1),size(img1,2),3);

% normalise both images
% if(max(img2(:))~=0)
%    img2 = img2 / max(img2(:));
% end;
if(max(img1(:))~=0)
    img1 = img1 / max(img1(:));
end;

%img2 = img2 * (mean(img1)/mean(img2));

%indx = 0.6;
%indx = 0.8;
indx = 1-pct;
if(length(map(:))>1)
    img2 = floor(img2*length(map))+1;
    img2 = ind2rgb(img2,map);
    
    out(:,:,1) = (indx) * img1 + (pct)*img2(:,:,1);
    out(:,:,2) = (indx) * img1 + (pct)*img2(:,:,2);
    out(:,:,3) = (indx) * img1 + (pct)*img2(:,:,3);
    
    out(find(out<0)) = 0;
    out(find(out>1)) = 1;
else
    
out(:,:,1) = (0.8) * img1 + colour(1)*(pct)*img2;
out(:,:,2) = (0.8) * img1 + colour(2)*(pct)*img2;
out(:,:,3) = (0.8) * img1 + colour(3)*(pct)*img2;

out = out/max(out(:));


end

return;


