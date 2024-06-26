function [DCM] = inversion_gonogo_laplace(DCM)

% MDP inversion using Variational Bayes
%
% Expects:
%--------------------------------------------------------------------------
% DCM.MDP   % MDP structure specifying a generative model
% DCM.field % parameter (field) names to optimise
% DCM.data  % struct of behavioral data
%
% Returns:
%--------------------------------------------------------------------------
% DCM.M     % generative model (DCM)
% DCM.Ep    % Conditional means (structure)
% DCM.Cp    % Conditional covariances
% DCM.F     % (negative) Free-energy bound on log evidence
% 
% This routine inverts (cell arrays of) trials specified in terms of the
% stimuli or outcomes and subsequent choices or responses. It first
% computes the prior expectations (and covariances) of the free parameters
% specified by DCM.field. These parameters are log scaling parameters that
% are applied to the fields of DCM.MDP. 
%
% If there is no learning implicit in multi-trial games, only unique trials
% (as specified by the stimuli), are used to generate (subjective)
% posteriors over choice or action. Otherwise, all trials are used in the
% order specified. The ensuing posterior probabilities over choices are
% used with the specified choices or actions to evaluate their log
% probability. This is used to optimise the MDP (hyper) parameters in
% DCM.field using variational Laplace (with numerical evaluation of the
% curvature).
%
%__________________________________________________________________________
% Copyright (C) 2005 Wellcome Trust Centre for Neuroimaging

% Karl Friston
% $Id: spm_dcm_mdp.m 7120 2017-06-20 11:30:30Z spm $

% OPTIONS
%--------------------------------------------------------------------------

% prior expectations and covariance
%--------------------------------------------------------------------------
% prior_variance = 2^-1;

% Set up DCM
%--------------------------------------------------------------------------
pE = DCM.M.pE;
pC = DCM.M.pC;


% model specification
%--------------------------------------------------------------------------
M.L     = @(P,M,U,Y)spm_mdp_L(P,M,U,Y);  % log-likelihood function
M.pE    = pE;                            % prior means (parameters)
M.pC    = pC;                            % prior variance (parameters)
M.use_ddm = DCM.use_ddm;                 % indicate if want to use ddm
M.ddm_mapping = DCM.ddm_mapping;         % specify mapping of RL to DDM params if using DDM
M.priors = DCM.MDP;
M.noprint = 1;

% Variational Laplace
%--------------------------------------------------------------------------
[Ep,Cp,F] = spm_nlsi_Newton(M,DCM.U, DCM.Y);

% Store posterior densities and log evidnce (free energy)
%--------------------------------------------------------------------------
DCM.M   = M;
DCM.Ep  = Ep;
DCM.Cp  = Cp;
DCM.F   = F;
DCM.U = DCM.U;
DCM.pC = pC;


return

function L = spm_mdp_L(P,M,U,Y)
% log-likelihood function
% FORMAT L = spm_mdp_L(P,M,U,Y)
% P    - parameter structure
% M    - generative model
% data - inputs and responses
%__________________________________________________________________________

if ~isstruct(P); P = spm_unvec(P,M.pE); end

% retransform params
field = fieldnames(M.pE);


for i = 1:length(field)
    if (strcmp(field{i},'alpha_win') || strcmp(field{i},'alpha_loss') || strcmp(field{i},'alpha')...
            || strcmp(field{i},'w') || strcmp(field{i},'zeta') || strcmp(field{i},'contaminant_prob')) 
        params.(field{i}) = 1/(1+exp(-P.(field{i})));  
    elseif strcmp(field{i},'T')
        params.(field{i}) = 1.5*exp(P.(field{i})) / (exp(P.(field{i}))+1);
%     elseif (strcmp(field{i},'beta') || strcmp(field{i},'a') || strcmp(field{i},'rs') || ...
%         strcmp(field{i},'la') || strcmp(field{i},'pi_win') || strcmp(field{i},'pi_loss') || ...
%         strcmp(field{i},'pi') || strcmp(field{i},'outcome_sensitivity') || strcmp(field{i},'v'))
%         params.(field{i}) = exp(P.(field{i})); 
    elseif (strcmp(field{i},'a') || strcmp(field{i},'rs') || ...
        strcmp(field{i},'la') || strcmp(field{i},'outcome_sensitivity')) 
        params.(field{i}) = exp(P.(field{i})); 
    elseif strcmp(field{i},'beta') || strcmp(field{i},'pi_win') || strcmp(field{i},'pi_loss') || ...
        strcmp(field{i},'pi')|| strcmp(field{i},'v')
        params.(field{i}) = (P.(field{i}));         
    else
        fprintf("Warning: one of parameters not being properly transformed. See inversion_gonogo_laplace");
        error("error");
    end
end

% make sure the params that are not being fit are still passed into
% the likelihood function
priors_names = fieldnames(M.priors);
priors = M.priors;
for i = 1:length(priors_names)
    if ~isfield(params, priors_names{i})
        params.(priors_names{i}) = priors.(priors_names{i});
    end
end
settings.field = field;
settings.use_ddm = M.use_ddm;
settings.ddm_mapping = M.ddm_mapping;
L = likfun_gonogo(params,U,settings);
if (~isreal(L))
    sprintf('LL is NOT REAL for %s\n',U.subject);
end
  

clear('MDP')
    

%fprintf('LL: %f \n',L)

