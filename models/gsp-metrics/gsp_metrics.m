%% cleanup
clc; 
clear;
close all;

%% file params
current_folder = pwd;
gsp_folder = "/gsp-csvs";

gsp_path = current_folder + gsp_folder;

%% read in files
cd(gsp_path)
file = dir('*DownlinkWindows.csv');
cd ..

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
fprintf("Altitude(km) \tAvg(s) \t\tStd(s) \t\tMin(s),\tMax(s)\n")

for i=1:num_files
    Orbit(i).avg_gsp_len = mean(Orbit(i).gsp_length);
    Orbit(i).std_gsp_len =  std(Orbit(i).gsp_length);
    Orbit(i).min_gsp_len =  min(Orbit(i).gsp_length);
    Orbit(i).max_gsp_len =  max(Orbit(i).gsp_length);
    
    fprintf("(%d)%.1f \t%.2f \t\t%.3f \t\t[%.2f,\t%.2f]\n", i, Orbit(i).alt, ...
            Orbit(i).avg_gsp_len, Orbit(i).std_gsp_len, ...
            Orbit(i).min_gsp_len, Orbit(i).max_gsp_len)
end

%% print per day metrics
fprintf("\nMetrics by Day:\n")
fprintf("Altitude(km) \tAvg(gsp/day) \tMin,\tMax \t\tAvg(sec/day) \tStd \tMin(s),\t\tMax(s)\n")

for i=1:num_files
    dates_only = datetime(Orbit(i).dt, 'Format', 'yyyy-MM-dd');
    dates_only.Hour = 0; dates_only.Minute = 0; dates_only.Second = 0; % Normalize to midnight
    [group_idx, unique_dates] = findgroups(dates_only);
    
    Orbit(i).sum_sec_per_day = splitapply(@sum , Orbit(i).gsp_length, group_idx);
    Orbit(i).avg_gsp_per_day  = mean(splitapply(@numel, dates_only, group_idx));
    Orbit(i).min_gsp_per_day  =  min(splitapply(@numel, dates_only, group_idx));
    Orbit(i).max_gsp_per_day  =  max(splitapply(@numel, dates_only, group_idx));

    Orbit(i).avg_sec_per_day = mean(Orbit(i).sum_sec_per_day);
    Orbit(i).std_sec_per_day =  std(Orbit(i).sum_sec_per_day);
    Orbit(i).min_sec_per_day =  min(Orbit(i).sum_sec_per_day);
    Orbit(i).max_sec_per_day =  max(Orbit(i).sum_sec_per_day);
    
    fprintf("(%d)%.1f \t%.2f \t\t[%.2f,\t%.2f] \t\t%.3f \t%.3f \t[%.2f,\t%.2f]\n", ...
            i, Orbit(i).alt, Orbit(i).avg_gsp_per_day, ...
            Orbit(i).min_gsp_per_day, Orbit(i).max_gsp_per_day, ...
            Orbit(i).avg_sec_per_day, ...
            Orbit(i).std_sec_per_day, ...
            Orbit(i).min_sec_per_day, Orbit(i).max_sec_per_day)
end

