function c = movingAverage(y, span)
% c = movingAverage(y, span)
% Centered moving average of column vector y, matching the Curve Fitting
% Toolbox's smooth(y, span, 'moving'):
% - the window is span points, reduced by one if span is even
% - near the ends the window shrinks symmetrically (c(1) = y(1))
% - NaNs are ignored within each window

y = y(:);
n = numel(y);
span = min(floor(span), n);
width = span - 1 + mod(span, 2); % odd
is_nan = isnan(y);

if any(is_nan)
    % average of the non-NaN values = moving sum of values / moving count
    y0 = y;
    y0(is_nan) = 0;
    c = movingAverage(y0, span) ./ movingAverage(double(~is_nan), span);
    return
end
if width == 1
    c = y;
    return
end

c = filter(ones(width, 1)/width, 1, y);
c_begin = cumsum(y(1:width-2));
c_begin = c_begin(1:2:end) ./ (1:2:(width-2))';
c_end = cumsum(y(n:-1:n-width+3));
c_end = c_end(end:-2:1) ./ (width-2:-2:1)';
c = [c_begin; c(width:end); c_end];
