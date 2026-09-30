function hp = dashedline(x,y, width, varargin)
%DASHEDLINE Plot dashed line
% DASHEDLINE(X,Y) plots a straight dashed line on the current axis along X and
% Y, with dash and gaps equal to 2 points. X and Y should each have
% exactly two elements defining the start and end of the line
%
% DASHEDLINE(X,Y, WIDTH) plots a dashed line with dash and gaps equal to
% WIDTH points. 
%
% DASHEDLINE(X,Y, WIDTH, VARARGIN) passes VARARGIN to the line command
%
% H = DASHEDLINE(X,Y,...) returns a handle to the dashed line
%
%
% Example: 
%   x = get(gca,'XLim');
%   y = [0 0];
%   dashedline(x, y, 4)
%
% Note 1: the dash width is adjusted slightly to ensure a dash is present 
% at the beginning and end of the line
%
% Note 2: point measurement assumes the dashed line is plotted along the
% whole width or height of the axis, otherwise it will be slightly off.
% 1 pt = 1/72 in = .3528 mm
%
% Includes plotboxpos, Copyright 2010 Kelly Kearney

% Hannah Payne, July 30 2020

% Demo: 
%{
p = 1;
figure;
subplot(131)
set(gca,'XLim',[0 10],'YLim',[0 10])
for ii = 1:9
    dashedline(ii*[1 1], get(gca,'YLim'),ii^p); hold on
end
axis off; axis square
subplot(132)
set(gca,'XLim',[0 10],'YLim',[0 10])
for ii = 1:9
    dashedline(get(gca,'XLim'), ii*[1 1],ii^p); hold on
end
axis off; axis square
subplot(133)
set(gca,'XLim',[0 10],'YLim',[0 10])
for ii = 1:9
    x = [max(0, ii-5) min(10, ii+5)];
    y = [max(0, -ii+5) min(10, -ii+15)];
    dashedline(x,y,ii^p); hold on
end
axis off; axis square
export_fig('example.png','-r300','-nocrop')
%}

if ~exist('width','var') || isempty(width)
    a = 2;
else
    a = width;
end

ha = gca;
ylims = ylim;
xlims = xlim;

% Get the plotted area in points
temp_units = get(ha,'Units');
set(ha,'Units','points');
pos = plotboxpos(ha);
flag_vert = 0;
if diff(y) ==0 % horiz line
    L = pos(3);
elseif diff(x)==0 % vert
    L = pos(4);
    flag_vert = 1;
else % diag
    L = sqrt(sum(pos([3 4]).^2));
end

% Get the number of ticks
n = round(L/(a*2))*2+1;

% Get the dashes
if flag_vert
    ydash = (0:.5:n);
    xdash = linspace(x(1),x(2),length(ydash));
    ydash = ydash/n*(max(y)-min(y))+y(1);
else
    xdash = (0:.5:n);
    ydash = linspace(y(1),y(2),length(xdash));
    xdash = xdash/n*(max(x)-min(x))+x(1);
end
ydash(4:4:end) = NaN;
ydash(2:4:end) = [];
xdash(2:4:end) = [];

% Plot and restore default axis units
hp = line(ha, xdash, ydash,'Color','k',varargin{:});
set(ha,'Units',temp_units,'YLim',ylims, 'XLim', xlims);

end

function pos = plotboxpos(h)
%PLOTBOXPOS Returns the position of the plotted axis region
%
% pos = plotboxpos(h)
%
% This function returns the position of the plotted region of an axis,
% which may differ from the actual axis position, depending on the axis
% limits, data aspect ratio, and plot box aspect ratio.  The position is
% returned in the same units as the those used to define the axis itself.
% This function can only be used for a 2D plot.  
%
% Input variables:
%
%   h:      axis handle of a 2D axis (if ommitted, current axis is used).
%
% Output variables:
%
%   pos:    four-element position vector, in same units as h

% Copyright 2010 Kelly Kearney

% Check input

if nargin < 1
    h = gca;
end

if ~ishandle(h) || ~strcmp(get(h,'type'), 'axes')
    error('Input must be an axis handle');
end

% Get position of axis in pixels

currunit = get(h, 'units');
set(h, 'units', 'pixels');
axisPos = get(h, 'Position');
set(h, 'Units', currunit);

% Calculate box position based axis limits and aspect ratios

darismanual  = strcmpi(get(h, 'DataAspectRatioMode'),    'manual');
pbarismanual = strcmpi(get(h, 'PlotBoxAspectRatioMode'), 'manual');

if ~darismanual && ~pbarismanual
    
    pos = axisPos;
    
else

    dx = diff(get(h, 'XLim'));
    dy = diff(get(h, 'YLim'));
    dar = get(h, 'DataAspectRatio');
    pbar = get(h, 'PlotBoxAspectRatio');

    limDarRatio = (dx/dar(1))/(dy/dar(2));
    pbarRatio = pbar(1)/pbar(2);
    axisRatio = axisPos(3)/axisPos(4);

    if darismanual
        if limDarRatio > axisRatio
            pos(1) = axisPos(1);
            pos(3) = axisPos(3);
            pos(4) = axisPos(3)/limDarRatio;
            pos(2) = (axisPos(4) - pos(4))/2 + axisPos(2);
        else
            pos(2) = axisPos(2);
            pos(4) = axisPos(4);
            pos(3) = axisPos(4) * limDarRatio;
            pos(1) = (axisPos(3) - pos(3))/2 + axisPos(1);
        end
    elseif pbarismanual
        if pbarRatio > axisRatio
            pos(1) = axisPos(1);
            pos(3) = axisPos(3);
            pos(4) = axisPos(3)/pbarRatio;
            pos(2) = (axisPos(4) - pos(4))/2 + axisPos(2);
        else
            pos(2) = axisPos(2);
            pos(4) = axisPos(4);
            pos(3) = axisPos(4) * pbarRatio;
            pos(1) = (axisPos(3) - pos(3))/2 + axisPos(1);
        end
    end
end

% Convert plot box position to the units used by the axis

temp = axes('Units', 'Pixels', 'Position', pos, 'Visible', 'off', 'parent', get(h, 'parent'));
set(temp, 'Units', currunit);
pos = get(temp, 'position');
delete(temp);
end