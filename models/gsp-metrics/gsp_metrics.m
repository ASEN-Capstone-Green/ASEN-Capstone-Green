%% cleanup
clc; 
clear;
close all;

%% file params
current_folder = pwd;
gsp_folder = "../shared-model-data/gsp-csvs";

gsp_path = current_folder + gsp_folder;

%% read in files
cd(gsp_folder)
file = dir('*DownlinkWindows.csv');
cd(current_folder)

num_files = length(file);

for i=num_files:-1:1 % backwards to preallocate struct on 1st loop
    a = split(file(i).name,"km");
    Orbit(i).alt = str2double(a{1});
    
    Orbit(i).data = readtable([file(i).folder '\'  file(i).name], ...
                        "VariableNamingRule","preserve");

    Orbit(i).time = Orbit(i).data.("Downlink Window Start Time (s)");
    rows2delete = isnan(Orbit(i).time);

    Orbit(i).data(rows2delete,:) = [];

    Orbit(i).start_time = Orbit(i).data.("Downlink Window Start Time (s)");
    Orbit(i).gsp_length = Orbit(i).data.("Downlink Window Length (s)");

    Orbit(i).dt = datetime(Orbit(i).start_time, ...
                           'ConvertFrom','posixtime','TimeZone','UTC');
end


%% print per orbit metrics
fprintf("Metrics by Ground Station Pass:\n")
fprintf("Altitude(km) \tAvg(s) \t\tStd(s) \t\tMin(s),\tMax(s) \t\tTyp Gap(s)\tMax Gap\n")

for i=1:num_files
    Orbit(i).avg_gsp_len = mean(Orbit(i).gsp_length);
    Orbit(i).std_gsp_len =  std(Orbit(i).gsp_length);
    Orbit(i).min_gsp_len =  min(Orbit(i).gsp_length);
    Orbit(i).max_gsp_len =  max(Orbit(i).gsp_length);

    gaps = diff(Orbit(i).start_time);
    Orbit(i).avg_gap = median(gaps);
    Orbit(i).longest_gap = max(gaps);
    
    fprintf("(%d)%.1f \t%.2f \t\t%.3f \t\t[%.2f,\t%.2f] \t%.2f\t%.2f\n", i, Orbit(i).alt, ...
            Orbit(i).avg_gsp_len, Orbit(i).std_gsp_len, ...
            Orbit(i).min_gsp_len, Orbit(i).max_gsp_len, ...
            Orbit(i).avg_gap, Orbit(i).longest_gap)
end

%% print per day metrics
fprintf("\nMetrics by Day:\n")
fprintf("Altitude(km) \tAvg(gsp/day) \tMin,\tMax \t\tMed(sec/day) \tStd \tMin,\tMax\n")


for i=1:num_files
    dates_only = datetime(Orbit(i).dt, 'Format', 'yyyy-MM-dd');
    dates_only.Hour = 0; dates_only.Minute = 0; dates_only.Second = 0; % Normalize to midnight
    [group_idx, unique_dates] = findgroups(dates_only);
    
    Orbit(i).sum_sec_per_day = splitapply(@sum , Orbit(i).gsp_length, group_idx);
    Orbit(i).avg_gsp_per_day  = mean(splitapply(@numel, dates_only, group_idx));
    Orbit(i).min_gsp_per_day  =  min(splitapply(@numel, dates_only, group_idx));
    Orbit(i).max_gsp_per_day  =  max(splitapply(@numel, dates_only, group_idx));

    Orbit(i).avg_sec_per_day = mean(Orbit(i).sum_sec_per_day);
    Orbit(i).med_sec_per_day = median(Orbit(i).sum_sec_per_day);
    Orbit(i).std_sec_per_day = std(Orbit(i).sum_sec_per_day);
    Orbit(i).min_sec_per_day = min(Orbit(i).sum_sec_per_day);
    Orbit(i).max_sec_per_day = max(Orbit(i).sum_sec_per_day);
    
    fprintf("(%d)%.1f \t%.2f \t\t[%.2f,\t%.2f] \t\t%.3f \t%.2f \t[%.1f,\t%.1f]\n", ...
            i, Orbit(i).alt, Orbit(i).avg_gsp_per_day, ...
            Orbit(i).min_gsp_per_day, Orbit(i).max_gsp_per_day, ...
            Orbit(i).med_sec_per_day, ...
            Orbit(i).std_sec_per_day, ...
            Orbit(i).min_sec_per_day, Orbit(i).max_sec_per_day)
end

%% compute by week metrics
fprintf("\nMetrics by Week:\n")
fprintf("Altitude(km) \tMed(gsp/week) \tMin,\tMax \t\tMed(s/week) \tMin,\tMax\n")

for i=1:num_files
    dates_only = datetime(Orbit(i).dt, 'Format', 'yyyy-MM-dd');
    dates_only.Hour = 0; dates_only.Minute = 0; dates_only.Second = 0; % Normalize to midnight
    week_numbers = week(dates_only);
    [group_idx_week, unique_weeks] = findgroups(week_numbers);

    % Group passes by calendar week, then exclude the first and last weeks
    week_start = dateshift(Orbit(i).dt, 'start', 'week');
    first_week = min(week_start);
    last_week = max(week_start);

    keep_pass = week_start ~= first_week & week_start ~= last_week;

    temp_gsp_len = Orbit(i).gsp_length(keep_pass);
    [group_idx_week, ~] = findgroups(week_start(keep_pass));

    Orbit(i).sum_sec_per_week = ...
        splitapply(@sum, temp_gsp_len, group_idx_week);

    gsp_per_week = splitapply(@numel, temp_gsp_len, group_idx_week);
    Orbit(i).med_gsp_per_week = median(gsp_per_week);
    Orbit(i).min_gsp_per_week = min(gsp_per_week);
    Orbit(i).max_gsp_per_week = max(gsp_per_week);

    Orbit(i).med_sec_per_week = median(Orbit(i).sum_sec_per_week);
    Orbit(i).min_sec_per_week = min(Orbit(i).sum_sec_per_week);
    Orbit(i).max_sec_per_week = max(Orbit(i).sum_sec_per_week);
    
    fprintf("(%d)%.1f \t%.2f \t\t[%.2f,\t%.2f] \t\t%.3f \t[%.1f,%.1f]\n", ...
            i, Orbit(i).alt, Orbit(i).med_gsp_per_week, ...
            Orbit(i).min_gsp_per_week, Orbit(i).max_gsp_per_week, ...
            Orbit(i).med_sec_per_week, ...
            Orbit(i).min_sec_per_week, Orbit(i).max_sec_per_week)
end
