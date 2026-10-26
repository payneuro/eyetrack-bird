function plot3dcone(p1, p2, radius, color)
    % Function to plot a 3D cone between points p1 and p2 with a given radius and color
    %
    % Parameters:
    % p1     - Starting point of the cone [x, y, z]
    % p2     - Tip of the cone [x, y, z]
    % radius - Radius of the cone's base
    % color  - Color of the cone in RGB format or color string (e.g., 'r' for red)

    % Calculate the direction vector and cone height
    dir_vec = p2 - p1;
    height = norm(dir_vec);

    % Create the cone along the z-axis
    [x_cone, y_cone, z_cone] = cylinder([radius, 0], 50); % Cone from base radius to 0
    z_cone = z_cone * height; % Scale the cone to the desired height

    % Calculate the rotation needed to align the cone's axis with dir_vec
    if height > 0
        % Compute the rotation vector and angle
        R = rotationBetween([0, 0, 1], dir_vec);

        % Rotate the cone's coordinates
        for i = 1:numel(x_cone)
            % Apply rotation matrix to each point
            new_coords = R * [x_cone(i); y_cone(i); z_cone(i)];
            x_cone(i) = new_coords(1);
            y_cone(i) = new_coords(2);
            z_cone(i) = new_coords(3);
        end
    end

    % Translate the cone to the starting position p1
    x_cone = x_cone + p1(1);
    y_cone = y_cone + p1(2);
    z_cone = z_cone + p1(3);

    % Plot the cone
    surf(x_cone, y_cone, z_cone, 'FaceColor', color, 'EdgeColor', 'none');

    % Create a circular cap (lid) for the base of the cone
    theta = linspace(0, 2*pi, 50);
    x_lid = radius * cos(theta);
    y_lid = radius * sin(theta);
    z_lid = zeros(size(theta));

    % Rotate the lid to match the cone's orientation
    if height > 0
        for i = 1:numel(x_lid)
            lid_coords = R * [x_lid(i); y_lid(i); z_lid(i)];
            x_lid(i) = lid_coords(1);
            y_lid(i) = lid_coords(2);
            z_lid(i) = lid_coords(3);
        end
    end

    % Translate the lid to the base position p1
    x_lid = x_lid + p1(1);
    y_lid = y_lid + p1(2);
    z_lid = z_lid + p1(3);

    % Plot the cap
    fill3(x_lid, y_lid, z_lid, color, 'EdgeColor', 'none'); % Lid
end
