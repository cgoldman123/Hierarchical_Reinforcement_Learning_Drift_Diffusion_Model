function [lik, latents] = likfun_gonogo(x,data,settings)
    sigmoid_adjusted = @(x) 1 ./ (1 + exp(-x*.125));
    dbstop if error
    rng(23);
    % Likelihood function for Go/NoGo task.
    
    % USAGE: [lik, latents] = likfun_gonogo(x,data)
    %
    % INPUTS:
    %   x - parameters:
    %      
    %   data - structure with the following fields
               % rt
               % trial_type
               % c (choices)
               % r (rewards)
    %           
    %
    % OUTPUTS:
    %   lik - log-likelihood
    %   latents - structure with the following fields:
    %           .v - [N x 1] drift rate
    %           .P - [N x 1] probability density of Go
    %           .RT_mean - [N x 1] mean response time for Go
    %
    % Carter Goldman and Sam Gershman, 2024
    
    % specify settings
    use_ddm = settings.use_ddm;
    field = settings.field;
    ddm_mapping = settings.ddm_mapping;
    
    
    % if fitted_params isn't passed in, initialize to false because not
    % dealing with fitted params
    if ~isnan(data.r(1))
        fitting = true;
    else
        fitting = false;
    end
    
    
    % set parameters
    beta = x.beta;
    zeta = x.zeta;
    pi_win = x.pi_win;
    pi_loss = x.pi_loss;
    a = x.a;
    alpha_win = x.alpha_win;
    alpha_loss = x.alpha_loss;
    T = x.T;
    rs = x.rs;
    la = x.la;
    outcome_sensitivity = x.outcome_sensitivity;
    pi = x.pi;
    alpha = x.alpha;
    w = x.w;
    v = x.v;
     
    
    % if the general parameters (outcome sensitivity, pi, and alpha) are
    % being fit, use them for the value of the specific parameters 
    if any(ismember(field,'outcome_sensitivity'))
        rs = outcome_sensitivity;
        la = outcome_sensitivity;
    end
    if any(ismember(field,'pi'))
        pi_win = pi;
        pi_loss = pi;
    end
    if any(ismember(field,'alpha'))
        alpha_win = alpha;
        alpha_loss = alpha;
    end
    
   
    
    % initialization
    lik = 0; 

    % state/action mapping to value
    Q = zeros(4,2);
    % state mapping to value
    V = zeros(4,1);
    mx = 1.5 - T;  % max reaction time is total trial time - non decision time
    states = data.trial_type;
    
    for t = 1:data.N
        % data for current trial
        c = data.c(t)+1;            % choice: 1 for no go, 2 for go
        r = data.r(t);              % reward: 0,1,-1
        s = states(t);              % trial type: 1 for go to win, 2 for go to avoid losing
                                    % 3 for no go to win, 4 for no go to avoid losing
  
        
        % calculate expected value qval
        qval = zeta*(Q(s,2)-Q(s,1));
                                    
        % calculate pavlovian influence
        if s == 1 || s == 3
            pav = pi_win*V(s);
        elseif s == 2 || s == 4
            pav = pi_loss*V(s);
        end
        
        % calculate go bias
        go = beta;
        

        
                                    
        %%%% GET PROBABILITY OF GO RESPONSE
        if use_ddm
            % Set v,w,a to 0 if they are not free parameters (i.e., their value
            % comes from qval,go,pav, etc)
            if ~any(strcmp(field,'v')); v = 0;end
            if ~any(strcmp(field,'w')); w = 0;end
            if ~any(strcmp(field,'a')); a = 0;end
            
            % drift rate v
            for i = 1:length(ddm_mapping.drift)
                var_name = ddm_mapping.drift{i};
                v = v + eval(var_name);
            end
            % starting bias w
            if ~~length(ddm_mapping.bias)
                for i = 1:length(ddm_mapping.bias)
                    var_name = ddm_mapping.bias{i};
                    w = w + eval(var_name);
                end
                w = sigmoid_adjusted(w);
            end
            
            % decision threshold a
            for i = 1:length(ddm_mapping.thresh)
                var_name = ddm_mapping.thresh{i};
                a = a + eval(var_name);
            end
            
            go_probability = integral(@(y) wfpt(y,-v,a,w),0,mx);
            % prevent negative action probability due to floating point
            % subtraction
            if (go_probability > .9999)
                go_probability = .9999;
            end
                
            action_probs = [1-go_probability go_probability];
        else
            weight_go = Q(s,2) + beta + pav;
            weight_nogo = Q(s,1);
            go_probability = (exp(weight_go) / (exp(weight_go)+exp(weight_nogo)))*(1-zeta) + (zeta/2);
            action_probs = [1-go_probability go_probability];
        end
        
        %%%% Fitting DATA %%%%
        if fitting
            action_probability = action_probs(c);
            %%% Fit reaction time pdf if go response and DDM %%%%
            if c == 2 && use_ddm
                % Wiener first passage time distribution calculates probability density that
                % the diffusion process hits the lower boundary at data.rt(t) - T. 
                % We pass in negative drift rate so lower boundary becomes "go"
                time_after_nondecision = max(T,data.rt(t)-T);
                P = wfpt(time_after_nondecision,-v,a,w);  
            else
                P = action_probability;
            end
            
        %%%% SIMULATING DATA %%%%
        else
            c = randsample(1:2, 1, true, action_probs);
            % for go trials, simulate reaction time
            if c == 2
                reaction_time = (0.5*a/v)*tanh(0.5*a*v)+T;
                data.rt(t) = min(reaction_time,1.5);
            end
            action_probability = action_probs(c);
            P = action_probability;
            % create reward matrix for 4 trial types: GTW, GAL, NGW,
            % NGAL
            rewardMatrix = [0, 1; -1, 0; 0, 1; -1, 0]; 
            if s == 1 || s ==2
                did_correct_choice = c == 2;
            elseif s == 3 || s ==4
                did_correct_choice = c == 1;
            end
            % prob_win is 80% if did correct thing, 20% otherwise
            prob_win = 0.2 + 0.6 * did_correct_choice;
            r = randsample(rewardMatrix(s,:), 1, true,[(1-prob_win) prob_win]); 
        end
        
        
        %%%% Accumulate log likelihood %%%%
        if P < 0
            disp(['Negative probability density calculated for', data.subject]);
            disp(x);
        end
        if isnan(P) || P==0; P = realmin; end % avoid NaNs and zeros in the logarithm
        lik = lik + log(P);
        
        % update values
        % if win trial
        if s == 1 || s == 3
            Q(s,c) = Q(s,c) + alpha_win*(r*rs - Q(s,c));
            V(s) = V(s) + alpha_win*(r*rs -V(s));
        % if loss trial
        elseif s == 2 || s == 4
            Q(s,c) = Q(s,c) + alpha_loss*(r*la - Q(s,c));
            V(s) = V(s) + alpha_loss*(r*la - V(s));
        end
        
        % store latent variables
        if use_ddm
            latents.v(t,1) = v;
            %latents.P(t,1) = 1/(1+exp(-a*v));
            %latents.RT_mean(t,1) = (0.5*a/v)*tanh(0.5*a*v)+T;
        end
        latents.P(t,1) = P;
        latents.action_probabilities(t) = action_probability;
        latents.r(t) = r;
        latents.c(t) = c;
        latents.rt = data.rt;
        latents.trial_type = data.trial_type;
           
    end
    
end 