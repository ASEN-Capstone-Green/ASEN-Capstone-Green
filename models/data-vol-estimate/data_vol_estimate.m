clc; 
clear;
close all;

%% flags
% this flag controls whether storage cap line is plotted, makes plot much
% harder to read as the storage cap is much larger than the used storage
PLOT_CAP_BITS = 0;

%% defined constants
earth.R = 6371; % km
earth.M = 5.9722e24; % kg
earth.mu = 3.9860044e5; % km^3/s^2

%% defined parameters
storage_capacity_bits = 8*16e9; % bits (16 GB)

orbit.altitude = 550; % km
% orbit.inclination = 97.59; % degrees
orbit.period = 2*pi*sqrt((orbit.altitude+earth.R)^3/earth.mu); % s
orbits.per_day = 24*3600/orbit.period; % orbits/day

% camera.polling_rate = 10e3; % Hz
camera.events_per_object = 2000;
camera.bits_per_event = 32; % bits
camera.avg_data_window = 100e-3; % seconds/object
camera.data_rate = camera.events_per_object * camera.bits_per_event / camera.avg_data_window; % bits/s

telemetry.polling_rate = 5; % Hz
telemetry.data_packet_sz = 8; % bits
telemetry.data_rate = telemetry.data_packet_sz * telemetry.polling_rate; % bits/s

h_and_s.polling_rate = 5; % Hz
h_and_s.num_temp_sensors = 5;
h_and_s.data_packet_sz = 8*h_and_s.num_temp_sensors; % bits
h_and_s.data_rate = h_and_s.data_packet_sz * h_and_s.polling_rate; % bits/s

% comms.data_rate = 150e3; % bits/s (150 kbps)
comms.data_rate = 10e6; % bits/s (10 Mbps)

dt_fmt = "dd/MM/uuuu HH:mm:ss.SSS";
dt_opts = {"TimeZone","UTC","Format",dt_fmt};
gsp_starts = [
    datetime("26/06/2027 05:30:00",dt_opts{:});
    datetime("26/06/2027 07:05:30",dt_opts{:});
    datetime("26/06/2027 17:30:00",dt_opts{:});
    datetime("26/06/2027 19:05:30",dt_opts{:});
    datetime("27/06/2027 05:30:00",dt_opts{:}); % just duplicated timestamps for now
    datetime("27/06/2027 07:05:30",dt_opts{:});
    datetime("27/06/2027 17:30:00",dt_opts{:});
    datetime("27/06/2027 19:05:30",dt_opts{:});
    % datetime("28/06/2027 05:30:00",dt_opts{:});
    % datetime("28/06/2027 07:05:30",dt_opts{:});
    % datetime("28/06/2027 17:30:00",dt_opts{:});
    % datetime("28/06/2027 19:05:30",dt_opts{:});
    %         DD/MM/YYYY HH:MM:SS
]; 
    
gsp_ends = [
    datetime("26/06/2027 05:38:00",dt_opts{:});
    datetime("26/06/2027 07:08:30",dt_opts{:});
    datetime("26/06/2027 17:38:00",dt_opts{:});
    datetime("26/06/2027 19:08:30",dt_opts{:});
    datetime("27/06/2027 05:38:00",dt_opts{:});
    datetime("27/06/2027 07:08:30",dt_opts{:});
    datetime("27/06/2027 17:38:00",dt_opts{:});
    datetime("27/06/2027 19:08:30",dt_opts{:});
    % datetime("28/06/2027 05:38:00",dt_opts{:});
    % datetime("28/06/2027 07:08:30",dt_opts{:});
    % datetime("28/06/2027 17:38:00",dt_opts{:});
    % datetime("28/06/2027 19:08:30",dt_opts{:});
    %         DD/MM/YYYY HH:MM:SS
];

% Supply these flags from an operations plan, or generate them for a
% probabilistic study, e.g. missed_passes = rand(size(gsp_starts)) < miss_probability.
missed_passes = false(size(gsp_starts));
missed_passes(5) = true;
missed_passes(7:8) = true;
missed_passes(10) = true;

%% simulation parameters
dt_s = 60; % step time size in seconds
% you can increase dt_s to speed up the sim, but you may lose accuracy if
% it is too large relative to the pass durations and data gen windows

sim_start = min(gsp_starts);
sim_end = min(gsp_starts) + days(2); % currently hardcoded
% sim_end = min(gsp_starts) + days(3);

num_events = 300; % events over the range
% num_events = 450;

window_s = seconds(sim_end - sim_start);
latest_start_s = window_s - camera.avg_data_window;

data_starts = sim_start + seconds(rand(num_events,1)*latest_start_s);
data_ends = data_starts + seconds(camera.avg_data_window);

%% run the simulation

nominal_gen_rate_bps = telemetry.data_rate + h_and_s.data_rate;
data_gen_rate_bps = camera.data_rate;

log = simulate_storage(sim_start, sim_end, dt_s, storage_capacity_bits, ...
    nominal_gen_rate_bps,data_gen_rate_bps, comms.data_rate, ...
    data_starts,data_ends, ...
    gsp_starts, gsp_ends, missed_passes);

%% plot the results
figure;
subplot(2,1,1);
hold on;
xlabel("Time (UTC) HH:MM:SS")
ylabel("Storage bits (count)")
plot(log.TimeUTC, log.StorageBits, 'LineWidth', 1.5);
if PLOT_CAP_BITS
    yline(storage_capacity_bits, '--k','LineWidth',1.5);
    legend("Used Storage","Max Storage",Location="northwest")
else
    legend("Used Storage",Location="northwest")   
end

subplot(2,1,2);
hold on;
xlabel("Time (UTC) HH:MM:SS")
ylabel("bits (count)")
plot(log.TimeUTC(1:end), log.GeneratedBits, 'LineWidth',1.5);
plot(log.TimeUTC(1:end), log.DownlinkedBits, 'LineWidth',1.5);
plot(log.TimeUTC(1:end), log.DroppedBits, 'LineWidth',1.5);
num_missed_passes = sum(missed_passes);
if num_missed_passes > 0
    for i = 1:numel(gsp_starts)
        if missed_passes(i)
            xline(gsp_starts(i), '--k', 'LineWidth', 1.5);
        end
    end
    legend("Generated","Downlinked","Dropped","Missed Pass")
else
    legend("Generated","Downlinked","Dropped")
end

%% metrics
% fprintf("Camera rate passed: %.0f bps\n", camera.data_rate);
% fprintf("Camera windows passed: %d\n\n", numel(data_starts));

fprintf("Camera window duration: %.3f s\n", ...
    sum(seconds(data_ends - data_starts)));
fprintf("Expected camera bits: %.0f\n\n", ...
    camera.data_rate * sum(seconds(data_ends - data_starts)));

fprintf("Logged generated bits: %.0f\n", sum(log.GeneratedBits));
