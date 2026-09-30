function b = robustLineFit(x, y)
% b = robustLineFit(x, y)
% Robust straight-line fit y = b(1) + b(2)*x, matching the coefficients of
% the Statistics Toolbox's robustfit(x, y) with its defaults: bisquare
% weights (tuning constant 4.685), iteratively reweighted least squares with
% leverage-adjusted residuals and a MAD scale estimate. Rows with NaN in x or
% y are ignored.

tune = 4.685;
keep = ~isnan(x(:)) & ~isnan(y(:));
y = y(keep);
X = [ones(nnz(keep), 1) x(keep)];
[n, p] = size(X);
if n <= p
    error('robustLineFit needs more than %i points', p)
end

% Ordinary least squares start, and leverage of each point
[Q, R] = qr(X, 0);
b = R \ (Q'*y);
E = X / R;
h = min(0.9999, sum(E.*E, 2));
adjfactor = 1 ./ sqrt(1 - h);

tiny_s = 1e-6 * std(y);
if tiny_s == 0; tiny_s = 1; end
tol = sqrt(eps);
b0 = zeros(size(b));
for iter = 1:51
    if iter > 1 && all(abs(b - b0) <= tol*max(abs(b), abs(b0)))
        break
    elseif iter == 51
        warning('robustLineFit: iteration limit reached')
        break
    end
    r_adj = (y - X*b) .* adjfactor;
    r_sorted = sort(abs(r_adj));
    s = median(r_sorted(p:end)) / 0.6745; % MAD, skipping the p smallest
    u = r_adj / (max(s, tiny_s) * tune);
    w = (abs(u) < 1) .* (1 - u.^2).^2; % bisquare
    b0 = b;
    sw = sqrt(w);
    b = (X .* sw) \ (y .* sw);
end
