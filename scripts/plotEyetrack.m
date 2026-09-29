function plotEyetrack(data_root, dir_roots)
% plotEyetrack(data_root, dir_roots)
% Plots summary across birds

stats = table;
filepath_eyes = [];
for ii = 1:length(dir_roots)
    a = strfind(dir_roots{ii},'_');
    filepath_eye = [dir_roots{ii}(1:a(end)-1) '_all'];
    filepath_eyes{ii} = filepath_eye;
    stats_curr = getfield(load(fullfile(data_root, filepath_eye,'head_calibration_template.mat')),'Ht');
    stats = [stats; stats_curr];
end
stats.filepath = filepath_eyes(:);
disp(stats)

figure; 
wun = ones(height(stats),1);
plot(wun, stats.theta_eye,'ok'); hold on
plot(wun*2, 90-stats.phi_eye,'ok');

mean_theta = mean(stats.theta_eye);
std_theta = std(stats.theta_eye);
plot(1, mean_theta,'+r','LineWidth',2); hold on
mean_phi = mean(90-stats.phi_eye);
std_phi = std(90-stats.phi_eye);
plot(2, mean_phi,'+r','LineWidth',2);

result = sprintf('Theta = %.1f+-%.1f, phi = %.1f+-%.1f, n = %i, mean +- stdev\n', mean_theta, std_theta, mean_phi, std_phi, height(stats));
disp(result)
title(result)%,'FontSize',8
labelArray = {'Horizontal angle','Vertical angle';'from center','above beak'};
tickLabels = strtrim(sprintf('%s\\newline%s\n', labelArray{:}));
set(gca,'XTick',[1 2], 'XTickLabel',tickLabels)
ylabel('Angle (deg)')
ylim([0 70])
xlim([0.5 2.5])
fixticks


%%
stats = table;
filepath_eyes = [];
for ii = 1:length(dir_roots)
    a = strfind(dir_roots{ii},'_');
    filepath_eye = [dir_roots{ii}(1:a(end)-1) '_all'];
    filepath_eyes{ii} = filepath_eye;
    stats_curr = getfield(load(fullfile(data_root, filepath_eye,'head_calibration_stats.mat')),'stats');
    stats = [stats; stats_curr];
end
stats.filepath = filepath_eyes(:);
disp(stats)


fprintf('Mean pupil-CC distance (mm): %.3f+-%.3f (mean +- stdev)\n',mean(stats.mean_pupil_cc), std(stats.mean_pupil_cc))

mu_std_theta = mean(stats.std_theta);
mu_std_phi = mean(stats.std_phi);
sigma_std_theta = std(stats.std_theta);
sigma_std_phi = std(stats.std_phi);
n = height(stats);
fprintf(['Stdev. horizontal eye angle %.1f +- %.1f°, '...
    'vertical eye angle %.1f +- %.1f (mean+-SEM)\n'],...
mu_std_theta, sigma_std_theta/sqrt(n),...
    mu_std_phi, sigma_std_phi/sqrt(n));

fprintf('Median angular eye deviation %.1f +- %.1f°(mean+-SEM, n = %i sessions)\n',...
mean(stats.median_overall), std(stats.median_overall)/sqrt(n), n)

%   fprintf(['mean %.0f frames per bird, range %i - %i left eye \n'...
%     'mean %.0f frames per bird, range %i - %i right eye \nn = %i birds\n'],...
%     mean(stats.nframes(:,1)), min(stats.nframes(:,1)), max(stats.nframes(:,1)),...
%     mean(stats.nframes(:,2)), min(stats.nframes(:,2)), max(stats.nframes(:,2)),...
%      height(stats))
 

