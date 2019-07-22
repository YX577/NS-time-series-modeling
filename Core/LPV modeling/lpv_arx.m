function [Theta,sigmaW,SigmaTh,criteria] = lpv_arx(x,y,xi,order,options)

na = order(1);
nb = order(2);
pa = order(3);
[~,N] = size(y);

%-- Constructing the representation basis
switch options.basis.type
    case 'fourier'
        g = ones(pa,N);
        for j=1:(pa-1)/2
            g(2*j,:) = sin(j*xi(1,:));
            g(2*j+1,:) = cos(j*xi(1,:));
        end
    case 'hermite'
        g = ones(pa,N);
        g(2,:) = 2*xi;
        for j=3:pa
            g(j,:) = 2*xi.*g(j-1,:) - 2*(j-1)*g(j-2,:);
        end        
end

if isfield(options.basis,'indices')
    g = g(options.basis.indices,:);
    pa = sum(options.basis.indices);
end

%-- Constructing the lifted signal
Y = zeros(pa,N);
X = zeros(pa,N);
for j=1:pa
    X(j,:) =  x.*g(j,:);
    Y(j,:) = -y.*g(j,:);
end

%-- Constructing the regression matrix
PhiX = zeros((nb+1)*pa,N-na);
PhiY = zeros(na*pa,N-na);
tau = na+1:N;
for i=1:na
    PhiY((1:pa)+(i-1)*pa,:) = Y(:,tau-i);
end
for i=0:nb
    PhiX((1:pa)+i*pa,:) = X(:,tau-i);
end
Phi = [PhiY; PhiX];

%-- Computing the OLS parameter estimates
Theta = y(:,tau)/Phi;
yhat = [zeros(1,na), Theta*Phi];
err = y(:,tau) - yhat(:,tau);
sigmaW = var(err);

Theta = reshape(Theta,pa,na+nb+1);
A = Theta(:,1:na);
B = Theta(:,na+1:end);

SigmaTh = sigmaW*eye((na+nb+1)*pa)/(Phi*Phi');

%-- Performance criteria
criteria.rss = sum(err.^2);
criteria.rss_sss = criteria.rss/sum(y.^2);
criteria.lnL = -(1/2)*( sum(log(2*pi*sigmaW) + err.^2/sigmaW) );
criteria.bic = log(N)*na*pa - 2*criteria.lnL;