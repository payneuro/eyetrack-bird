function plot3deye(p, v, r_eye, r_pupil, color)
    % Function to plot a 3D eye-like shape with a filled circular pupil on its surface
    %
    % Parameters:
    % p        - Center of the sphere (eye) [x, y, z]
    % v        - Direction vector for the pupil on the surface
    % r_eye    - Radius of the sphere (eye)
    % r_pupil  - Radius of the pupil circle relative to the sphere's radius

    % Normalize the direction vector v
    v = v / norm(v);

    % Create the sphere (eye)
    [x_sphere, y_sphere, z_sphere] = sphere(50);

    % Scale and position the sphere (eye)
    x_sphere = r_eye * x_sphere + p(1);
    y_sphere = r_eye * y_sphere + p(2);
    z_sphere = r_eye * z_sphere + p(3);

    % Plot the grey sphere (eye)
    surf(x_sphere, y_sphere, z_sphere, 'FaceColor', color, 'EdgeColor', 'none');
    hold on;

    % Define the radius of the slightly larger sphere for the pupil
    r_larger = 1.01 * r_eye; % Radius slightly larger than the eye sphere

    % Generate spherical coordinates for the small circular section (pupil)
    [theta, phi] = meshgrid(linspace(0, 2*pi, 50), linspace(0, r_pupil / r_eye, 50));

    % Convert the spherical coordinates to Cartesian coordinates relative to the larger sphere
    x_pupil = r_larger * sin(phi) .* cos(theta);
    y_pupil = r_larger * sin(phi) .* sin(theta);
    z_pupil = r_larger * cos(phi);

    % Align the pupil with the direction vector v using rotation
    z_axis = [0, 0, 1]; % Original z-axis direction

    % Calculate rotation matrix to align z-axis with direction vector v
    if norm(cross(z_axis, v)) > 0
        R = rotationBetween(z_axis, v);

        % Rotate pupil points
        for i = 1:numel(x_pupil)
            rotated_point = R * [x_pupil(i); y_pupil(i); z_pupil(i)];
            x_pupil(i) = rotated_point(1);
            y_pupil(i) = rotated_point(2);
            z_pupil(i) = rotated_point(3);
        end
    end

    % Translate the pupil to the center of the sphere
    x_pupil = x_pupil + p(1);
    y_pupil = y_pupil + p(2);
    z_pupil = z_pupil + p(3);

    % Plot the pupil as a black filled section on the larger sphere
    surf(x_pupil, y_pupil, z_pupil, 'FaceColor', 'k', 'EdgeColor', 'none');

    % Set axis properties
    axis equal;
    grid on;
end
