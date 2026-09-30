function plot_handles = detectPupilCRPlot(I, p, plot_handles, pupil, CRout, points, option_crop_width, option_enhance_contrast)
if p.plot_on
    a = linspace(0,2*pi,40);
    CRx = CRout(1,:);
    CRy = CRout(2,:);
    CRr = CRout(3,:);
    

    start_x = 1;
    start_y = 1;
    if isnan(pupil(1))
        option_crop_width = false;
        [stop_y, stop_x] = size(I);
    end
    if exist('option_crop_width','var') && option_crop_width 
        r = option_crop_width;
        start_x = max(1,round(pupil(1)-r/2));
        stop_x = min(size(I, 2),round( pupil(1) + r/2));
        start_y = max(1,round(pupil(2)-r/2)); % rows = y
        stop_y = min(size(I, 1), round(pupil(2) + r/2));
        I  = I(start_y:stop_y, start_x:stop_x); % cols = x    
    else 
        option_crop_width = false;
    end
    
        
    if exist('option_enhance_contrast','var') && option_enhance_contrast
%         I = adapthisteq(I/255);
        I = imadjust(I/255);
    end
    
    if ~isfield(plot_handles,'img') || ~isgraphics(plot_handles.img)
        
        % Plot image

        plot_handles.img = imagesc(plot_handles.ah, start_x, start_y, I);  colormap(plot_handles.ah, gray);   axis(plot_handles.ah,'image')

        hold(plot_handles.ah,'on')
        
        % Plot CRs
        cr_colors = flipud(jet(p.nCRs+6));
        for ii = 1:p.nCRs
            plot_handles.cr{ii} = plot(plot_handles.ah, CRr(ii).*cos(a) + CRx(ii), CRr(ii).*sin(a)+CRy(ii),'Color',cr_colors(ii,:));
        end
        plot_handles.crs = plot(plot_handles.ah, CRx, CRy,'+','Color',cr_colors(1,:));
        
        % Plot pupil ellipse
        plot_handles.pupil_line = line(plot_handles.ah, pupil(3)*cos(a)*cos(pupil(5)) - sin(pupil(5))*pupil(4)*sin(a) + pupil(1), ...
            pupil(3)*cos(a)*sin(pupil(5)) + cos(pupil(5))*pupil(4)*sin(a) + pupil(2),...
            'Color','y');
        
        % Plot pupil points
        plot_handles.pupil_center = plot(plot_handles.ah, pupil(1), pupil(2),'+y','LineWidth',2, 'MarkerSize',10);
        
        
        plot_handles.pupil_all = plot(plot_handles.ah, points.px0, points.py0,'.c');
        plot_handles.pupil_inliers = plot(plot_handles.ah, points.px1, points.py1,'.y');
        
    else
        
        % Plot image
        if option_crop_width
            set(plot_handles.img, 'CData',I,'XData',start_x, 'YData', start_y);    
            xlim([start_x stop_x])
            ylim([start_y stop_y])
        else
            set(plot_handles.img, 'CData',I);
        end
        
        % Plot CRs
        for ii = 1:p.nCRs
            set(plot_handles.cr{ii}, 'XData',CRr(ii).*cos(a) + CRx(ii), 'YData',CRr(ii).*sin(a)+CRy(ii));
        end
        set(plot_handles.crs, 'XData', CRx, 'YData', CRy);
        
        % Plot pupil ellipse
        set(plot_handles.pupil_line, 'XData', pupil(3)*cos(a)*cos(pupil(5)) - sin(pupil(5))*pupil(4)*sin(a) + pupil(1), ...
            'YData',  pupil(3)*cos(a)*sin(pupil(5)) + cos(pupil(5))*pupil(4)*sin(a) + pupil(2));
        
        % Plot pupil points
        set(plot_handles.pupil_center, 'XData', pupil(1), 'YData', pupil(2));
        set(plot_handles.pupil_all, 'XData', points.px0, 'YData', points.py0);
        set(plot_handles.pupil_inliers, 'XData', points.px1, 'YData', points.py1);
        %
    end
    drawnow limitrate
end
