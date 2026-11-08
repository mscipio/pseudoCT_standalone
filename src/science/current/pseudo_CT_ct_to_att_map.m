function [att_map] = pseudo_CT_ct_to_att_map(CT, varargin)
%PSEUDO_CT_CT_TO_ATT_MAP Convert a CT volume into an attenuation map.
%   ATT_MAP = PSEUDO_CT_CT_TO_ATT_MAP(CT, KVP)
%   CT is a numeric CT volume in Hounsfield units, or a char path to a NIfTI
%   file (read with SPM). KVP selects the conversion: 100, 120, 130 or 140 for
%   the positive-kVp formulas, or -1 (GE, the default), -80, -100, -110, -120,
%   -130 or -140 for the Siemens-type formulas. Other KVP values display a
%   message and return an all-zero map.
%   ATT_MAP has the size of CT. Water is 0.096 in the output units (cm^-1).
%   Based on the Bai et al. (2003) and Burger et al. (2002) approaches for GE.
%   The no-argument form calls read_raw_data, which is not part of this
%   repository; do not rely on it.
%   Side effects: none. Errors: none raised by this function.
%   Originally dated 07/15/2010. Minimum supported MATLAB: R2010b.

if nargin == 0
    CT = read_raw_data(0);
end

if ischar(CT)
    CT_fname = CT;
    %CT = read_raw_data(CT_fname);
    CT = spm_read_vols(spm_vol(CT_fname));
end

Kvp = -1;

if nargin == 2
    Kvp = varargin{1};
end

mask = CT <= 0;

cte_GE = 5.9687; % Just in case is needed this is the constant to replace instead of 5.09, 5.76, ...
att_map = zeros(size(CT));
switch Kvp
    case 100
        att_map = 0.096*(1 + (1.0*10^-3.*CT.*mask) + (5.09*10^-4.*CT.*(1-mask)));
    case 120
        att_map = 0.096*(1 + (1.0*10^-3.*CT.*mask) + (5.76*10^-4.*CT.*(1-mask)));
    case 130
        att_map = 0.096*(1 + (1.0*10^-3.*CT.*mask) + (6.05*10^-4.*CT.*(1-mask)));
    case 140
        att_map = 0.096*(1 + (1.0*10^-3.*CT.*mask) + (6.40*10^-4.*CT.*(1-mask)));
    case -1 % GE type:
        att_map = 0.096*(1 + (1.0*10^-3.*CT.*mask) + (5.9687*10^-4.*CT.*(1-mask)));
    case -80 % Siemens (Carney et al. (2006) paper).
        mask = CT <= 50;
        a = 3.64*10^-5; b = 6.26*10^-2;
        att_map = (0.096*(1 + 1.0*10^-3.*CT)).*mask + (1-mask).*(a.*(CT + 1000) + b); 
   case -100 % Siemens (Carney et al. (2006) paper).
        mask = CT <= 52;
        a = 4.43*10^-5; b = 5.44*10^-2;
        att_map = (0.096*(1 + 1.0*10^-3.*CT)).*mask + (1-mask).*(a.*(CT + 1000) + b);
   case -110 % Siemens (Carney et al. (2006) paper).
        mask = CT <= 43;
        a = 4.92*10^-5; b = 4.88*10^-2;
        att_map = (0.096*(1 + 1.0*10^-3.*CT)).*mask + (1-mask).*(a.*(CT + 1000) + b);
    case -120 % Siemens (Carney et al. (2006) paper).
        mask = CT <= 47;
        a = 5.10*10^-5; b = 4.71*10^-2;
        att_map = (0.096*(1 + 1.0*10^-3.*CT)).*mask + (1-mask).*(a.*(CT + 1000) + b);
    case -130 % Siemens (Carney et al. (2006) paper).
        mask = CT <= 37;
        a = 5.51*10^-5; b = 4.24*10^-2;
        att_map = (0.096*(1 + 1.0*10^-3.*CT)).*mask + (1-mask).*(a.*(CT + 1000) + b);
    case -140 % Siemens (Carney et al. (2006) paper).
        mask = CT <= 30;
        a = 5.64*10^-5; b = 4.08*10^-2;
        att_map = (0.096*(1 + 1.0*10^-3.*CT)).*mask + (1-mask).*(a.*(CT + 1000) + b);
    otherwise
        display('Need to choose a right KVp: 100, 120, 130 or 140!');
end
