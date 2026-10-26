function result = plotEyetrack(Ht, stats)
% result = plotEyetrack(Ht, stats)
% Plot and summarize eye angles across birds. Ht and stats are the tables
% from runEyetrackAll, one row per bird (stack them with [Ht1; Ht2; ...]).
% result - one-line text summary (also printed)

figure;
wun = ones(height(Ht),1);
h = plot(wun, Ht.theta_eye,'ok'); hold on
plot(wun*2, 90-Ht.phi_eye,'ok');

mean_theta = mean(Ht.theta_eye);
std_theta = std(Ht.theta_eye);
h(2) = plot(1, mean_theta,'+r','LineWidth',2); hold on
mean_phi = mean(90-Ht.phi_eye);
std_phi = std(90-Ht.phi_eye);
plot(2, mean_phi,'+r','LineWidth',2);

result = sprintf('Theta = %.1f+-%.1f, phi = %.1f+-%.1f, n = %i birds, mean +- stdev', mean_theta, std_theta, mean_phi, std_phi, height(Ht));
if height(Ht) == 1
    title(sprintf('Theta = %.1f, phi = %.1f (1 bird)', mean_theta, mean_phi))
else
    title(result)
end
legend(h, {'Bird', 'Mean'})
labelArray = {'Horizontal angle','Vertical angle';'from center','above beak'};
tickLabels = strtrim(sprintf('%s\\newline%s\n', labelArray{:}));
set(gca,'XTick',[1 2], 'XTickLabel',tickLabels)
ylabel('Angle (deg)')
ylim([0 70])
xlim([0.5 2.5])
fixticks
drawnow

n = height(stats);
if n == 1 % no spread across birds to report
    result = sprintf(['Theta = %.1f, phi = %.1f deg (1 bird). Pupil-CC distance %.3f mm. ' ...
        'SD of eye angle %.1f deg horizontal, %.1f vertical. Median angular eye deviation %.1f deg'], ...
        mean_theta, mean_phi, stats.mean_pupil_cc, stats.std_theta, stats.std_phi, stats.median_overall);
else
    result = sprintf(['%s. Pupil-CC distance %.3f+-%.3f mm (mean +- stdev). ' ...
        'SD of eye angle %.1f +- %.1f deg horizontal, %.1f +- %.1f vertical (mean +- SEM). ' ...
        'Median angular eye deviation %.1f +- %.1f deg (mean +- SEM, n = %i birds)'], result, ...
        mean(stats.mean_pupil_cc), std(stats.mean_pupil_cc), ...
        mean(stats.std_theta), std(stats.std_theta)/sqrt(n), mean(stats.std_phi), std(stats.std_phi)/sqrt(n), ...
        mean(stats.median_overall), std(stats.median_overall)/sqrt(n), n);
end
disp(result)
