%--------------------------------------------------------------------------
% This script demonstrates the identification of a non-linear system
% determined by the Duffing equation:
%
%       y'' + delta*y' + alpha*y + beta*y^3 = gamma'F(t)
%
% when the excitation force F(t) is a normally and identically distributed
% noise.
% In the identification, it is assumed that the system is LPV where the
% scheduling variable is the displacement variable, so that:
%
%       y'' + a1*y' + a2(t)*y = gamma'F(t)
%
% where:
%
%       a1 = delta   and a2(t) = (alpha* + beta*y^2)
%
% Identification is performed in discrete time by means of LPV-AR models,
% in an output-only fashion, namely, only the response of the system
% (displacement) is used in the identification.
%
% Created by : David Avendano - July 2019
%--------------------------------------------------------------------------

%-- Clearing the workspace
clear
close all
clc

%% Part 1 : Creating a simulation of the system's response to NID excitation

%-- Simulation parameters
T = 800;                                                                    % Analysis period (s)
fs0 = 128;                                                                  % Sampling frequency for simulation
N = T*fs0;                                                                  % Number of samples
t = linspace(1/fs0,T,N);                                                    % Time vector (s)

%-- Creating the excitation force
f = randn(1,N);                                                             % Sampling from a normally random variable
F = @(t) NIDexcitation(t,f,fs0);                                            % Creating the excitation based on the provided NID sample

%-- Parameters of the non-linear system
alpha = (2*pi*2)^2;                                                         % Stiffness parameter (linear)
beta = 80;                                                                  % Stiffness parameter (cubic)
delta = 2*0.01*sqrt(alpha);                                                 % Damping parameter (1% damping ratio)
gamma = 100;                                                                % Input gain
theta = [alpha beta gamma delta];                                           % Parameter vector
x0 = [0 0]';                                                                % Initial state of the system

%-- Initializing computation matrices
[~,y] = ode45( @(t,y)DuffingEq(t,y,F,theta), t, x0 );                       % Integrating the non-linear system

%% Part 1b : Resampling the signal
% Signal is resampled into the bandwidth of higher response power. Correct
% setting is essential for accurate identification of the non-linear
% system.

close all
clc

%-- Properties of the downsampled signal
N = 1e4;                                                                    % Signal length
T0 = 1e4;                                                                   % Time to start analysis
fs = 32;                                                                    % Analysis sampling frequency

%-- Resampling
x = resample(y(:,1),fs,fs0);                                                % Resampling the signal
t = t(1:fs0/fs:end);                                                        % Resampling the time vector

%-- Trimming the signals
x = x(T0+(1:N));                                                            % Trimming the signal into the desired analysis period
t = t(T0+(1:N))- t(1e4);                                                    % Trimming the time vector into the desired analysis period

%% Part 2 : Identification via LPV-AR models - Selection of the model order
% Standard model order selection is carried out. A range of model orders is
% proposed ( via 'na_max' ), while a plausible value of the functional
% basis order is selected ( 'pa' ). LPV-AR models are then calculated for
% various model structures within the range 1 up to na_max. Then different
% performance criteria are compared to determine the best model order.

close all
clc

%-- Fixing the input variables and training/validation indices
ind_train = false(1,N);
ind_train(1:N/2) = true;                                                    % Indices for training of the LPV-AR model
ind_val = ~ind_train;                                                       % Indices for validation
signals.response = x(ind_train)';                                           % Response (displacement)
signals.scheduling_variables = x(ind_train)';                               % Scheduling variable (also displacement!)
sign_validation.response = x(ind_val)';                                     % Response (displacement)
sign_validation.scheduling_variables = x(ind_val)';                         % Scheduling variable (also displacement!)

%-- Structural parameters of the LPV-AR model
na_max = 12;                                                                % Maximum model order
pa = 4;                                                                     % Functional basis order
options.basis.type = 'hermite';                                             % Type of functional basis

%-- Initializing computation matrices
rss_sss = zeros(2,na_max);                                                  % Residual sum of squares over series sum of squares
lnL = zeros(2,na_max);                                                      % Log likelihood
bic = zeros(1,na_max);                                                      % Bayesian Information Criterion

%-- Model order selection loop
for na = 1:na_max
    
    %-- Calculating training performance criteria
    order = [na pa];
    M = estimate_lpv_ar(signals,order,options);
    rss_sss(1,na) = M.performance.rss_sss;
    lnL(1,na) = M.performance.lnL;
    bic(na) = M.performance.bic;
    
    %-- Calculating validation performance criteria
    [~,criteria] = simulate_lpv_ar(sign_validation,M);
    rss_sss(2,na) = criteria.rss_sss;
    lnL(2,na) = criteria.lnL;
end

%-- Plotting performance criteria
figure('Position',[100 100 1200 400])
subplot(131)
semilogy(2:na_max,rss_sss(:,2:na_max)*100)
grid on
xlabel('Model order')
ylabel('RSS/SSS [%]')
legend({'Training','Validation'})

subplot(132)
plot(2:na_max,lnL(:,2:na_max))
grid on
xlabel('Model order')
ylabel('Log-likelihood')
legend({'Training','Validation'})

subplot(133)
plot(2:na_max,bic(2:na_max))
grid on
xlabel('Model order')
ylabel('BIC')

figure('Position',[100 600 800 400])
bins = linspace(-10,10,40);
histogram(x(ind_train),bins)
hold on
histogram(x(ind_val),bins)
grid on
legend({'Training','Validation'})
xlabel('Scheduling variable \xi')

%% Part 3 : Identification via LPV-AR models - Basis order analysis
% Based on the model order selected on Part 2, here an analysis of the
% coefficients of the LPV-AR model is carried out. The objective of this
% analysis is to determine if some coefficients may be deemed as zero. For
% that purpose a hypothesis test is performed by assuming that the
% coefficients are Gaussian distributed with zero mean and covariance
% determined by the estimation algorithm.
% If the coefficients are lower than the threshold for a specific Type I
% error probability, then with such probability the coefficient can be
% deemed as equal to zero.
% If a the coefficients of a basis are consistently equal to zero, then the
% respective basis may be rejected from the model, thus leading to a more
% compact model. 

close all
clc

clear lnL rss_sss bic

%-- Structural parameters of the LPV-AR model
na = 5;                                                                     % Model order
pa = 4;                                                                     % Functional basis order
order = [na pa];                                                            % Order parameters
options.basis.type = 'hermite';                                             % Type of functional basis

%-- Estimating the LPV-AR model for the training data
M = estimate_lpv_ar(signals,order,options);
rss_sss(1,1) = M.performance.rss_sss;
lnL(1,1) = M.performance.lnL;

%-- Validating the LPV-AR model on the validation data
[xhat0,criteria] = simulate_lpv_ar(sign_validation,M);
rss_sss(2,1) = criteria.rss_sss;
lnL(2,1) = criteria.lnL;

%-- Chi square test for the LPV-AR coefficients
% This test evaluates the hypothesis that the LPV-AR coefficients are zero.
% For that purpose, it is assumed that each coefficient is Gaussian
% distributed with mean zero and covariance equal to that provided by the
% estimation algorithm.

chi2_theta = reshape( M.performance.chi2_theta, pa, na );                   % Test statistic (chi squared distributed)
alph_chi2 = 10.^(-4:-1);                                                    % Probability of type I error (rejecting the null hypothesis)
rho = chi2inv( 1-alph_chi2, 1 );                                            % Threshold for error probablity

Mrk = 'oxd^';

figure('Position',[100 100 600 800])
pt = zeros(pa,1);
for j=1:pa
    pt(j) = semilogy( 1:na, chi2_theta(j,:), ['--',Mrk(j)], 'MarkerSize', 10, 'LineWidth', 2 );
    hold on
end

grid on
for i=1:numel(rho)
    semilogy( [1 na], rho(i)*[1 1], 'k' )
    text( 1.1, 1.2*rho(i), ['\alpha = ',num2str(alph_chi2(i))] )
end
set(gca,'XTick',1:na)
legend(pt, {'$f_0(\xi)$','$f_1(\xi)$','$f_2(\xi)$','$f_3(\xi)$'},'Interpreter','latex')
xlabel('Model order')
ylabel('\chi^2 test statistic')

%-- Selected basis indices
basis_indices = max( chi2_theta > rho(3) ,[],2);

%% Validating the obtained LPV-AR model in the validation data
close all
clc

opts = options;
opts.basis.indices = basis_indices;

%-- Estimating the LPV-AR model for the training data
M1 = estimate_lpv_ar(signals,order,opts);
rss_sss(1,2) = M1.performance.rss_sss;
lnL(1,2) = M1.performance.lnL;

%-- Validating the LPV-AR model on the validation data
[xhat,criteria] = simulate_lpv_ar(sign_validation,M1);
rss_sss(2,2) = criteria.rss_sss;
lnL(2,2) = criteria.lnL;

figure('Position',[100 100 900 800])
subplot(211)
plot(t(ind_train),xhat0,t(ind_train),xhat,t(ind_train),x(ind_val))
xlim([30 60])
grid on
xlabel('Time (s)')
ylabel('Displacement')
legend({'Complete LPV-AR model','Reduced LPV-AR model','Original'})

subplot(212)
pwelch([xhat0;xhat;x(ind_val)']')
legend({'Complete LPV-AR model','Reduced LPV-AR model','Original'})

figure('Position',[1000 100 900 800])
A0 = M.a;
AA = zeros(size(A0));
AA(basis_indices,:) = M1.a;
for i=1:pa
    subplot(pa,1,i)
    plot(A0(i,:),['--',Mrk(1)])
    hold on
    if basis_indices(i)
        plot(AA(i,:),['--',Mrk(1)])
        legend({'Complete','Reduced'})
    else
        legend('Complete')
    end
    grid on
    ylabel(['$a_{i,',num2str(i),'}$'],'Interpreter','latex')
    xlabel('AR order')
    set(gca,'XTick',1:na)
end

%% Model based analysis
% Analysis of the dynamics of the identified LPV-AR model
close all
clc

m = 400;
Xi_range = linspace(-6,6,m);
[Pyy,omega,omegaN,zeta] = MBA_lpv_ar(M1,Xi_range);

figure('Position',[100 100 900 800])

subplot(211)
imagesc(Xi_range,omega*fs/(2*pi),10*log10(Pyy))
axis xy
hold on
plot(Xi_range,omegaN*fs/(2*pi),'w.')
xlabel('Displacement')
ylabel('Frequency (Hz)')
grid on
cbar = colorbar;
cbar.Label.String = 'PSD [dB]';
set(gca,'YTick',0:2:fs/2)
ylim([0 fs/2])

subplot(212)
dx = 0.04*[0 1];
dy = 0.08*[0 1];
for i=1:na
    for j=1:m
        imagesc(Xi_range(j)+dx,omegaN(i,j)*fs/(2*pi)+dy,100*zeta(i,j))
        hold on
    end
end
xlabel('Displacement')
ylabel('Frequency (Hz)')
xlim([-6 6])
ylim([0 fs/2])
axis xy
grid on
cbar = colorbar;
cbar.Label.String = 'Damping ratio [%]';