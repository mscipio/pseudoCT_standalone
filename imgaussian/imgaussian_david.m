function I=imgaussian_david(I,sigma,siz)
% IMGAUSSIAN filters an 1D, 2D color/greyscale or 3D image with an 
% Gaussian filter. This function uses for filtering IMFILTER or if 
% compiled the fast  mex code imgaussian.c . Instead of using a 
% multidimensional gaussian kernel, it uses the fact that a Gaussian 
% filter can be separated in 1D gaussian kernels.
%
% J=IMGAUSSIAN(I,SIGMA,SIZE)
%
% inputs,
%   I: The 1D, 2D greyscale/color, or 3D input image with 
%           data type Single or Double
%   SIGMA: The sigma used for the Gaussian kernel
%   SIZE: Kernel size (single value) (default: sigma*6)
% 
% outputs,
%   J: The gaussian filtered image
%
% note, compile the code with: mex imgaussian.c -v
%
% example,
%   I = im2double(imread('peppers.png'));
%   figure, imshow(imgaussian(I,10));
% 
% Function is written by D.Kroon University of Twente (September 2009)
%
% My own version coding for potential 3 different sigmas (on each
% direction);

if(~exist('siz','var')), siz=max(sigma)*6; end

if(sigma>0)
        if length(sigma) == 1
            sigma = [sigma sigma sigma];
        end
        % Make 1D Gaussian kernel
        x=-ceil(siz/2):ceil(siz/2);
        H = exp(-(x.^2/(2*sigma(1)^2)));
        H1 = H/sum(H(:));
        H = exp(-(x.^2/(2*sigma(2)^2)));
        H2 = H/sum(H(:));
        H = exp(-(x.^2/(2*sigma(3)^2)));
        H3 = H/sum(H(:));

        % Filter each dimension with the 1D Gaussian kernels\
        if(ndims(I)==1)
            I=imfilter(I,H1, 'same' ,'replicate');
        elseif(ndims(I)==2)
            Hx=reshape(H1,[length(H1) 1]);
            Hy=reshape(H2,[1 length(H2)]);
            I=imfilter(imfilter(I,Hx, 'same' ,'replicate'),Hy, 'same' ,'replicate');
        elseif(ndims(I)==3)
            if(size(I,3)<4) % Detect if 3D or color image
                Hx=reshape(H1,[length(H1) 1]);
                Hy=reshape(H2,[1 length(H2)]);
                for k=1:size(I,3)
                    I(:,:,k)=imfilter(imfilter(I(:,:,k),Hx, 'same' ,'replicate'),Hy, 'same' ,'replicate');
                end
            else
                Hx=reshape(H1,[length(H1) 1 1]);
                Hy=reshape(H2,[1 length(H2) 1]);
                Hz=reshape(H3,[1 1 length(H3)]);
                I=imfilter(imfilter(imfilter(I,Hx, 'same' ,'replicate'),Hy, 'same' ,'replicate'),Hz, 'same' ,'replicate');
            end
        else
            error('imgaussian:input','unsupported input dimension');
        end
end