function [P]   = GNG_spm_dcm_fit(P,use_parfor)
% Bayesian inversion of DCMs using Variational Laplace
% FORMAT [DCM] = spm_dcm_fit(P)
%
% P          - {N x M} DCM structure array (or filenames) from N subjects
% use_parfor - if true, will attempt to run in parallel (default: false)
%              NB: all DCMs are loaded into memory
%
% DCM  - Inverted (1st level) DCM structures with posterior densities
%__________________________________________________________________________
%
% This routine is just a wrapper that calls the appropriate dcm inversion
% routine for a set a pre-specifed DCMs.
%
% If called with a cell array, each column is assumed to contain 1st level
% DCMs inverted under the same model. Each row contains a different data
% set (or subject).
%__________________________________________________________________________
% Copyright (C) 2015 Wellcome Trust Centre for Neuroimaging

% Karl Friston
% $Id: spm_dcm_fit.m 7755 2019-12-16 13:19:28Z spm $

if nargin < 2, use_parfor = false; end

% get filenames and set up
%--------------------------------------------------------------------------
if ~nargin
    [P, sts] = spm_select([1 Inf],'^DCM.*\.mat$','Select DCM*.mat files');
    if ~sts, return; end
end
if ischar(P),   P = cellstr(P);  end
if isstruct(P), P = {P};         end

% Number of subjects (data) and models (of those data)
%--------------------------------------------------------------------------
[Ns,Nm] = size(P);

% Find model class and modality
%--------------------------------------------------------------------------
try, load(P{1}); catch, DCM = P{1}; end

model = spm_dcm_identify(DCM);

if isempty(model)    
    warning('unknown inversion scheme');
    return   
end

% Get data structure for each subject (column)
%--------------------------------------------------------------------------
for i = 1:Ns
    for j = 2:Nm
        switch model            
            case{'DEM'}
                P{i, j}.xY = P{i, 1}.Y;
            otherwise
                P{i, j}.xY = P{i, 1}.xY;
        end
    end
end

% Estimate
%--------------------------------------------------------------------------
if use_parfor
    % Estimate DCMs in parallel using parfor
    P = spm_dcm_load(P);
    
    parfor i = 1:numel(P)
        P{i} = fit_dcm(P{i}, model);
        
        fprintf('F for subject %s: %f \n', P{i}.subject{1}, P{i}.F);
    end
else
    % Estimate DCMs without parfor
    for i = 1:numel(P)
        try
            DCM = load(P{i});
            DCM = DCM.DCM;
        catch
            DCM = P{i}; 
        end
        P{i} = fit_dcm(DCM, model);
        fprintf('F for subject %s: %f \n', P{i}.subject{1}, P{i}.F);
        
    end
end
    
% -------------------------------------------------------------------------
function DCM = fit_dcm(DCM, model)
% Inverts a DCM. 
% DCM   - the DCM structure
% model - a string identifying the model type (see spm_dcm_identify)
    
switch model


    % behavioural Markov decision process model
    %----------------------------------------------------------------------
    case{'MDP'}
        DCM = inversion_gonogo_laplace(DCM);

    otherwise
        try
            DCM = feval(model, DCM);
        catch
            error('unknown DCM');
        end
end   