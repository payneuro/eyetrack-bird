function plot3darrow(p1, p2, cyl_radius, cone_radius, color)
    % Function to plot a 3D arrow between points p1 and p2 using a cylinder and a cone
    %
    % Parameters:
    % p1          - Starting point of the arrow [x, y, z]
    % p2          - Tip of the arrow [x, y, z]
    % cyl_radius  - Radius of the cylinder (arrow shaft)
    % cone_radius - Radius of the cone (arrowhead base)
    % color       - Color of the arrow in RGB format or color string (e.g., 'r' for red)

    % Calculate the direction vector and arrow length
    dir_vec = p2 - p1;
    arrow_length = norm(dir_vec);

    % Shaft parameters
    h_cylinder = 0.75 * arrow_length; % Height of the cylinder (shaft)

    % Create the cylinder (shaft of the arrow)
    [x_cyl, y_cyl, z_cyl] = cylinder(cyl_radius, 50);
    z_cyl = z_cyl * h_cylinder;

    % Create the cone (arrowhead)
    h_cone = 0.25 * arrow_length; % Height of the cone (arrowhead)
    [x_cone, y_cone, z_cone] = cylinder([cone_radius, 0], 50);
    z_cone = z_cone * h_cone + h_cylinder; % Position cone on top of the cylinder

    % Normalize the direction vector if it's not a zero vector
    if arrow_length > 0
        dir_vec = dir_vec / arrow_length;
    else
        dir_vec = [0, 0, 1]; % Default direction vector if p1 and p2 are the same
    end

    % Calculate the rotation matrix to align [0 0 1] with dir_vec
    rotation_axis = cross([0 0 1], dir_vec);
    rotation_angle = acos(dot([0 0 1], dir_vec));
    
    % Create a rotation matrix using Rodrigues' rotation formula if rotation is needed
    if norm(rotation_axis) > 0
        K = [0 -rotation_axis(3) rotation_axis(2);
             rotation_axis(3) 0 -rotation_axis(1);
             -rotation_axis(2) rotation_axis(1) 0];
        R = eye(3) + sin(rotation_angle) * K + (1 - cos(rotation_angle)) * (K^2);

        % Apply rotation to cylinder coordinates
        for i = 1:numel(x_cyl)
            new_coords = R * [x_cyl(i); y_cyl(i); z_cyl(i)];
            x_cyl(i) = new_coords(1);
            y_cyl(i) = new_coords(2);
            z_cyl(i) = new_coords(3);
        end

        % Apply rotation to cone coordinates
        for i = 1:numel(x_cone)
            new_coords = R * [x_cone(i); y_cone(i); z_cone(i)];
            x_cone(i) = new_coords(1);
            y_cone(i) = new_coords(2);
            z_cone(i) = new_coords(3);
        end
    end

    % Translate the cylinder and cone to the starting position p1
    x_cyl = x_cyl + p1(1);
    y_cyl = y_cyl + p1(2);
    z_cyl = z_cyl + p1(3);

    x_cone = x_cone + p1(1);
    y_cone = y_cone + p1(2);
    z_cone = z_cone + p1(3);

    % Plot the cylinder (shaft)
    surf(x_cyl, y_cyl, z_cyl, 'FaceColor', color, 'EdgeColor', 'none');

    % Plot the cone (arrowhead)
    surf(x_cone, y_cone, z_cone, 'FaceColor', color, 'EdgeColor', 'none');
end
