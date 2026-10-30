% Date: 07/15/2010;
% Name: CT_2_att_map.m;
% Function to convert a CT image into an attenuation map, following the Bai
% et al. approache (2003) and Burger et al (2002) for the GE!

function [att_map] = CT_2_att_map(CT, varargin)

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
