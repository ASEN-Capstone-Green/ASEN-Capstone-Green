function log = simulate_storage(sim_start, sim_end, dt_s, capacity_bits, ...
        nominal_gen_rate_bps, data_gen_rate_bps, downlink_rate_bps, ...
        data_gen_starts, data_gen_ends, ...
        pass_starts, pass_ends, missed_passes)
% Simulate storage over time. Pass windows must be datetime arrays in UTC.
% missed_passes(i) is true when pass i is unavailable.

    if numel(pass_starts) ~= numel(pass_ends) || ...
            numel(pass_starts) ~= numel(missed_passes)
        error("Pass start, end, and missed-pass arrays must have equal lengths.");
    end
    if numel(data_gen_starts) ~= numel(data_gen_ends)
        error("Data generation start and end arrays must have equal lengths.");
    end
    if dt_s <= 0
        error("dt_s must be positive.");
    end
    if capacity_bits < 0
        error("capacity_bits must be nonnegative.");
    end

    % compute needed time steps to preallocate arrays
    n = ceil(seconds(sim_end - sim_start) / dt_s);
    % Compute all time-step boundaries and durations at once.
    step_starts = sim_start + seconds((0:n-1)' * dt_s);
    step_ends = min(sim_end, sim_start + seconds((1:n)' * dt_s));
    step_durations_s = seconds(step_ends - step_starts);

    % preallocate arrays
    time = NaT(n + 1, 1, "TimeZone", "UTC");
    storage = zeros(n + 1, 1);
    generated = zeros(n, 1);
    downlinked = zeros(n, 1);
    dropped = zeros(n, 1);
    pass_active = false(n, 1);

    time(1) = sim_start;
   
    n_passes = numel(pass_starts);
    n_data_windows = numel(data_gen_starts);

    for k = 1:n
        % sum the usable part of each pass overlapping this step
        usable_pass_s = 0;
        for j = 1:n_passes
            if ~missed_passes(j)
                overlap_start = max(step_starts(k), pass_starts(j));
                overlap_end = min(step_ends(k), pass_ends(j));
                overlap = (overlap_end - overlap_start);
                % ignore negative overlap (no overlap)
                if overlap > 0
                    usable_pass_s = usable_pass_s + seconds(overlap);
                end
            end
        end
        % make sure we don't exceed step duration
        usable_pass_s = min(usable_pass_s, step_durations_s(k));

        % sum the usable part of each data gen window overlapping this step
        usable_data_gen_s = 0;
        for j = 1:n_data_windows
            overlap_start = max(step_starts(k), data_gen_starts(j));
            overlap_end = min(step_ends(k), data_gen_ends(j));
            overlap = (overlap_end - overlap_start);
            % ignore negative overlap (no overlap)
            if overlap > 0
                usable_data_gen_s = usable_data_gen_s + seconds(overlap);
            end
        end
        % make sure we don't exceed step duration
        usable_data_gen_s = min(usable_data_gen_s, step_durations_s(k));

        generated(k) = nominal_gen_rate_bps * step_durations_s(k) + ...
            data_gen_rate_bps * usable_data_gen_s;
        avail_downlink_bits = storage(k) + generated(k);
        downlinked(k) = min(downlink_rate_bps * usable_pass_s, avail_downlink_bits);

        after_tx = avail_downlink_bits - downlinked(k);
        dropped(k) = max(0, after_tx - capacity_bits);
        storage(k + 1) = min(capacity_bits, after_tx);
        pass_active(k) = usable_pass_s > 0;
        time(k + 1) = step_ends(k);
    end
    log = table(time(1:end-1), storage(1:end-1), generated, downlinked, dropped, ...
        pass_active, ...
        'VariableNames', {'TimeUTC', 'StorageBits', 'GeneratedBits', ...
                          'DownlinkedBits', 'DroppedBits', 'InUsablePass'});

end
