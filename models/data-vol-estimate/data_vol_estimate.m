clc;
clear;
close all;

%% flags
% plot the storage cap line (makes the storage plot hard to read, since
% the cap is much larger than the storage used)
PLOT_CAP_BITS = 1;
% on by default, as rerunning the sim can take some time
SAVE_FIGS = 1;

%% inputs
budget_xlsx = "Data_Processing_Budget.xlsx";   % source of all data rates
rng_seed = 1;                % fixed seed -> repeatable missed passes/requests

storage_capacity_bits = 8*32e9;     % bits (32 GB)
time_raw_data_stays_on_sys = 24*3600; % s, raw retention protocol (1 day)
sim_start_doy = 177;         % day of year to start sim (Jan 1 = 1)
sim_range_days = 7;          % days (first day is warm-up for raw storage)
dt_s = 60;                   % step size [s]; keep well below pass lengths

gsp_miss_rate = 0.05;        % fraction of passes that are missed
obj_detects_per_day = 300;
avg_data_window_s = 30;      % camera time per object [s]

% raw-request model: the ground can only ask for an object's raw video
% after its processed packet has been downlinked
raw_requests_per_day = 2;    % objects/day the ground asks for raw video on
raw_request_clip_s = 5;    % s of video requested per object (Inf = all)
request_latency_s = 0;       % s from processed packet on the ground to
                             % the request being onboard (0 = same pass)

orbit.altitude = 550;        % km (selects the pass CSV)

comms.downlink_data_rate = 150e3;  % bits/s (design 160 kbps, conservative)
comms.link_efficiency = 1.0;       % fraction left after headers/CRC/framing

%% data rates from the Data Budget sheet
src = load_data_budget(budget_xlsx);
disp(src(:, ["dir","subsystem","name","packet_bits","rate_hz", ...
    "gate","gate_duty"]));

raw  = aggregate_rates(src(src.dir == "in", :));
proc = aggregate_rates(src(src.dir == "out", :));

% the sheet's payload duty cycle should match the observation model here
cam = src(src.dir == "in" & src.gate == "observation", :);
sim_cam_duty = obj_detects_per_day * avg_data_window_s / 86400;
if ~isempty(cam) && abs(cam.duty(1) - sim_cam_duty) > 1e-3
    warning("Sheet payload duty %.4f ~= sim duty %.4f (detects/day x window).", ...
        cam.duty(1), sim_cam_duty);
end

%% downlink windows
dt_fmt = "dd/MM/uuuu HH:mm:ss.SSS";
dt_opts = {"TimeZone","UTC","Format",dt_fmt};

gsp_csv_name = sprintf("%dkmDownlinkWindows.csv", orbit.altitude);
gsp_csv_dir = "../shared-model-data/gsp-csvs";
gsp_tbl = readmatrix(fullfile(gsp_csv_dir, gsp_csv_name));

pass_start_s = gsp_tbl(:,1); % unix time
passlens = gsp_tbl(:,2);     % s

% Place the requested day of year in a year covered by the CSV. Adding the
% range as a duration handles a window that crosses New Year's.
all_gsp_starts = datetime(pass_start_s,'ConvertFrom','posixtime',dt_opts{:});
all_gsp_ends = all_gsp_starts + seconds(passlens);
csv_start = min(all_gsp_starts);
csv_end = max(all_gsp_ends);
sim_start = NaT('TimeZone','UTC','Format',dt_fmt);
sim_end = NaT('TimeZone','UTC','Format',dt_fmt);
for candidate_year = year(csv_start):year(csv_end)
    candidate_start = datetime(candidate_year,1,1,'TimeZone','UTC', ...
        'Format',dt_fmt) + days(sim_start_doy - 1);
    candidate_end = candidate_start + days(sim_range_days);
    if candidate_start >= csv_start && candidate_end <= csv_end
        sim_start = candidate_start;
        sim_end = candidate_end;
        break;
    end
end
if isnat(sim_start)
    error('No complete simulation window for day %d and %d days exists in the CSV date range.', ...
        sim_start_doy, sim_range_days);
end

% keep passes overlapping the sim interval
in_sim_range = all_gsp_starts <= sim_end & all_gsp_ends >= sim_start;
gsp_starts = all_gsp_starts(in_sim_range);
gsp_ends = all_gsp_ends(in_sim_range);

rng(rng_seed);
num_passes = numel(gsp_starts);
missed_passes = false(num_passes,1);
missed_passes(randperm(num_passes, round(gsp_miss_rate*num_passes))) = true;

%% object observations
% We don't control when objects cross the FOV, so windows are placed
% randomly and can overlap; overlapping windows add data (more pixel
% events on the sensor).
num_events = obj_detects_per_day * sim_range_days;
window_s = seconds(sim_end - sim_start);
latest_start_s = window_s - avg_data_window_s;

t_obs = sort(rand(num_events,1) * latest_start_s);
obsrv_starts = sim_start + seconds(t_obs);
obsrv_ends = obsrv_starts + seconds(avg_data_window_s);
num_obs = numel(obsrv_starts);

obs_requested = false(num_obs,1);
n_req = min(num_obs, round(raw_requests_per_day * sim_range_days));
obs_requested(randperm(num_obs, n_req)) = true;
obs_request_bits = raw.obs_bps * raw_request_clip_s;   % Inf -> whole window

%% run the simulation
cfg.sim_start = sim_start;
cfg.sim_end = sim_end;
cfg.dt_s = dt_s;
cfg.capacity_bits = storage_capacity_bits;
cfg.retention_s = time_raw_data_stays_on_sys;
cfg.downlink_rate_bps = comms.downlink_data_rate * comms.link_efficiency;
cfg.request_latency_s = request_latency_s;
cfg.pass_starts = gsp_starts;
cfg.pass_ends = gsp_ends;
cfg.missed_passes = missed_passes;
cfg.obs_starts = obsrv_starts;
cfg.obs_ends = obsrv_ends;
cfg.obs_requested = obs_requested;
cfg.obs_request_bits = obs_request_bits;
cfg.raw = raw;
cfg.proc = proc;

[log, summary] = simulate_storage(cfg);

%% plot the results
t = log.TimeUTC;
figure('Units', 'normalized', 'Position', [0.05 0.1 0.9 0.8]);
sgtitle("Data Volume Estimate (Downlink Rate of " + ...
    num2str(cfg.downlink_rate_bps/1e3) + " kbps, " + ...
    num2str(time_raw_data_stays_on_sys/3600) + " h raw retention)");

subplot(3,1,1); grid on; hold on;
area(t, [log.RawHKBits, log.RawCamBits, log.RawRequestedBits, ...
    log.ProcQueueBits] / 8e9, 'LineStyle', 'none');
leg = ["Raw housekeeping","Raw camera (unrequested)", ...
    "Raw camera (requested, pending)","Processed queue"];
if PLOT_CAP_BITS
    yline(storage_capacity_bits/8e9, '--k', 'LineWidth', 1.5);
    leg(end+1) = sprintf("Capacity (%.2f GB)", storage_capacity_bits/8e9);
end
legend(leg, Location="northwest");
ylabel("Storage (GB)");

subplot(3,1,2); grid on; hold on;
plot(t, cumsum(log.GenProcBits)/1e6, 'LineWidth', 1.5);
plot(t, cumsum(log.DownlinkProcBits)/1e6, 'LineWidth', 1.5);
plot(t, cumsum(log.DownlinkRawBits)/1e6, 'LineWidth', 1.5);
plot(t, cumsum(log.ExpiredRequestedBits)/1e6, 'LineWidth', 1.5);
legend("Processed generated","Processed downlinked", ...
    "Requested raw downlinked","Requested raw expired", Location="northwest");
ylabel("Cumulative (Mb)");

subplot(3,1,3); grid on; hold on;
plot(t, log.ProcQueueBits/1e3, 'LineWidth', 1.5);
for i = find(missed_passes)'
    xline(gsp_starts(i), '--k', 'LineWidth', 1);
end
if any(missed_passes)
    legend("Processed backlog","Missed pass", Location="northwest");
end
ylabel("Processed backlog (kb)");
xlabel("Time (UTC)");

if SAVE_FIGS
    data_rate_kbps = strrep(num2str(cfg.downlink_rate_bps/1e3),'.','_');
    print("data-vol-estimate-"+data_rate_kbps+"kbps", '-dpng', '-r600');
end

%% metrics
nd = sim_range_days;
fprintf("\n--- generation (per day) ---------------------------------\n");
fprintf("Raw:       sheet %8.2f Gb   sim %8.2f Gb\n", ...
    sum(src.bits_per_day_sheet(src.dir=="in"))/1e9, sum(log.GenRawBits)/nd/1e9);
fprintf("Processed: sheet %8.2f Mb   sim %8.2f Mb\n", ...
    sum(src.bits_per_day_sheet(src.dir=="out"))/1e6, sum(log.GenProcBits)/nd/1e6);

dl_cap = cfg.downlink_rate_bps * summary.usable_pass_s;
fprintf("\n--- downlink (per day) -----------------------------------\n");
fprintf("Usable pass time:     %8.1f s\n", summary.usable_pass_s/nd);
fprintf("Downlink capacity:    %8.2f Mb\n", dl_cap/nd/1e6);
fprintf("Processed sent:       %8.2f Mb (%.0f%% of capacity)\n", ...
    sum(log.DownlinkProcBits)/nd/1e6, 100*sum(log.DownlinkProcBits)/dl_cap);
fprintf("Requested raw sent:   %8.2f Mb\n", sum(log.DownlinkRawBits)/nd/1e6);
fprintf("Margin for raw:       %8.2f Mb  = %.1f s of camera video\n", ...
    (dl_cap - sum(log.DownlinkProcBits))/nd/1e6, ...
    (dl_cap - sum(log.DownlinkProcBits))/nd/raw.obs_bps);

fprintf("\n--- raw requests ------------------------------------------\n");
fprintf("Requested %d windows (%.1f Mb total)\n", summary.n_requested, ...
    summary.req_bits_target/1e6);
fprintf("  delivered %d, expired before delivery %d, still pending %d\n", ...
    summary.n_req_delivered, summary.n_req_lost, summary.n_req_pending);

lat = summary.proc_latency_s(~isnan(summary.proc_latency_s));
fprintf("\n--- storage / latency -------------------------------------\n");
fprintf("Peak storage:  %.2f GB of %.0f GB\n", max(log.StorageBits)/8e9, ...
    storage_capacity_bits/8e9);
fprintf("Raw evicted early (storage full): %.0f bits\n", sum(log.EvictedBits));
fprintf("Processed dropped:                %.0f bits\n", sum(log.DroppedProcBits));
fprintf("Detection -> ground latency (processed): median %.1f h, max %.1f h\n", ...
    median(lat)/3600, max(lat)/3600);

%% local functions
function r = aggregate_rates(T)
% Sum the sheet's packets into the rate buckets the sim uses.
    bps = T.packet_bits .* T.rate_hz .* T.gate_duty;
    r.cont_bps     = sum(bps(T.gate == "continuous"));
    r.obs_bps      = sum(bps(T.gate == "observation"));
    r.pass_bps     = sum(bps(T.gate == "pass"));
    r.per_obs_bits = sum(T.packet_bits(T.gate == "perobservation") .* ...
                         T.gate_duty(T.gate == "perobservation"));
end
