function [log, summary] = simulate_storage(cfg)
% SIMULATE_STORAGE  Onboard storage sim with a raw-data retention protocol.
%
% Storage holds three kinds of data:
%   1. Processed queue  - everything in the sheet's "Data Out" block. FIFO,
%                         highest downlink priority, never expires.
%   2. Raw camera data  - stored per observation window. The ground may
%                         request a window (or a clip of it) once that
%                         object's processed packet has reached the ground;
%                         requested bits downlink with whatever pass time
%                         is left after the processed queue is empty.
%   3. Raw housekeeping - all other "Data In" sources, stored per time step.
%                         Never requested in this model.
% Raw data (2 and 3) is deleted cfg.retention_s after it was taken, whether
% or not it was downlinked.
%
% If storage fills, space is freed in this order: oldest unrequested camera
% raw, oldest housekeeping raw, requested camera raw, and finally new
% processed data is dropped. Any of these means data was lost early.
%
% cfg fields
%   sim_start, sim_end        datetime (UTC)
%   dt_s                      step size [s]
%   capacity_bits             storage capacity [bits]
%   retention_s               raw retention time [s]
%   downlink_rate_bps         usable downlink rate [bits/s]
%   request_latency_s         time from a processed packet reaching the
%                             ground to its raw request being onboard [s]
%   pass_starts, pass_ends    datetime arrays
%   missed_passes             logical, true = pass unusable
%   obs_starts, obs_ends      datetime arrays, sorted; may overlap (bits add)
%   obs_requested             logical, ground will request this window
%   obs_request_bits          raw bits requested per window (Inf = all)
%   raw, proc                 structs of rates (from the Data Budget sheet):
%       .cont_bps      always on
%       .obs_bps       while the camera is on an object
%       .pass_bps      during usable passes
%       .per_obs_bits  once per object, at window end

    % ---- convert everything to seconds since sim_start (fast loops)
    t0 = cfg.sim_start;
    T  = seconds(cfg.sim_end - t0);
    dt = cfg.dt_s;
    if dt <= 0, error("dt_s must be positive."); end
    n  = ceil(T / dt);
    ss = (0:n-1)' * dt;               % step starts
    se = min(T, (1:n)' * dt);         % step ends
    dur = se - ss;

    ps = seconds(cfg.pass_starts(:) - t0);  % pass starts
    pe = seconds(cfg.pass_ends(:) - t0);    % pass ends
    usable = ~cfg.missed_passes(:);
    ps = ps(usable);  pe = pe(usable);
    [ps, ord] = sort(ps);  pe = pe(ord);
    np = numel(ps);                         % number of passes

    os = seconds(cfg.obs_starts(:) - t0);   % observation starts
    oe = seconds(cfg.obs_ends(:) - t0);     % observation ends
    m  = numel(os);
    % Windows may overlap (several objects in the FOV at once); their data
    % adds. The pointer logic below needs starts and ends both in order,
    % which holds for equal-length windows sorted by start.
    if any(diff(os) < 0) || any(diff(oe) < 0)
        error("Observation windows must be sorted with ends in the same order as starts.");
    end
    req      = logical(cfg.obs_requested(:));
    req_bits = cfg.obs_request_bits(:);
    if isscalar(req_bits), req_bits = repmat(req_bits, m, 1); end

    R = cfg.raw;  P = cfg.proc;  ret = cfg.retention_s;
    cap = cfg.capacity_bits;

    % ---- state
    hk = zeros(n,1);  hk_head = 1;  hk_total = 0;   % housekeeping chunks
    ob = zeros(m,1);  ob_total = 0;                 % camera raw per window
    ob_req = zeros(m,1);  ob_req_total = 0;         % requested, not yet sent
    req_target = zeros(m,1);  req_sent = zeros(m,1);  req_lost = zeros(m,1);
    obs_head = 1;          % oldest window still onboard
    next_end = 1;          % windows 1..next_end-1 have ended
    scan_obs = 1;          % first window that may overlap the current step
    first_pass = 1;
    proc_q = 0;  cum_pg = 0;  cum_pd = 0;
    proc_mark = nan(m,1);  % cum. processed bits at which window i's packet is out
    proc_dl_t = nan(m,1);  % time window i's processed packet was downlinked
    elig_t    = inf(m,1);  % earliest time its raw request can be served
    mark_ptr  = 1;

    % ---- logs
    Z = zeros(n,1);
    st_hk = Z; st_cam = Z; st_req = Z; st_proc = Z;
    gen_raw = Z; gen_proc = Z; dl_proc = Z; dl_raw = Z;
    exp_unreq = Z; exp_req = Z; evicted = Z; dropped_proc = Z;
    pass_active = false(n,1);  cam_active = false(n,1);

    for k = 1:n
        a = ss(k);  b = se(k);

        % usable pass time in this step
        while first_pass <= np && pe(first_pass) <= a
            first_pass = first_pass + 1;
        end
        pass_s = 0;  j = first_pass;
        while j <= np && ps(j) < b
            pass_s = pass_s + max(0, min(b, pe(j)) - max(a, ps(j)));
            j = j + 1;
        end
        pass_s = min(pass_s, dur(k));

        % camera time in this step, credited to each window
        while scan_obs <= m && oe(scan_obs) <= a
            scan_obs = scan_obs + 1;
        end
        cam_s = 0;  cam_bits = 0;  j = scan_obs;
        while j <= m && os(j) < b
            ov = max(0, min(b, oe(j)) - max(a, os(j)));
            if ov > 0
                x = R.obs_bps * ov;
                ob(j) = ob(j) + x;  cam_bits = cam_bits + x;
                cam_s = cam_s + ov;
            end
            j = j + 1;
        end
        % cam_s is object-seconds, not wall time: overlapping windows each
        % produce their own pixel events, so it isn't capped at dur(k)

        % generation
        hk_new = R.cont_bps * dur(k) + R.pass_bps * pass_s;
        hk(k) = hk_new;  hk_total = hk_total + hk_new;
        proc_new = P.cont_bps * dur(k) + P.pass_bps * pass_s + P.obs_bps * cam_s;

        while next_end <= m && oe(next_end) <= b     % windows ending now
            i = next_end;
            ob(i) = ob(i) + R.per_obs_bits;
            cam_bits = cam_bits + R.per_obs_bits;
            if req(i)
                req_target(i) = min(req_bits(i), ob(i));
                ob_req(i) = req_target(i);
                ob_req_total = ob_req_total + ob_req(i);
            end
            proc_new = proc_new + P.per_obs_bits;
            proc_mark(i) = cum_pg + proc_new;
            next_end = next_end + 1;
        end
        ob_total = ob_total + cam_bits;
        proc_q = proc_q + proc_new;  cum_pg = cum_pg + proc_new;
        gen_raw(k) = hk_new + cam_bits;  gen_proc(k) = proc_new;

        % downlink: processed queue first
        budget = cfg.downlink_rate_bps * pass_s;
        d = min(budget, proc_q);
        proc_q = proc_q - d;  cum_pd = cum_pd + d;  budget = budget - d;
        dl_proc(k) = d;

        % objects whose processed packet is now on the ground
        while mark_ptr < next_end && proc_mark(mark_ptr) <= cum_pd + 1e-6
            proc_dl_t(mark_ptr) = b;
            elig_t(mark_ptr) = b + cfg.request_latency_s;
            mark_ptr = mark_ptr + 1;
        end

        % then requested raw, oldest (closest to expiry) first
        i = obs_head;  sent = 0;
        while budget > 0 && i < mark_ptr
            if ob_req(i) > 0 && elig_t(i) <= a
                x = min(budget, ob_req(i));
                ob_req(i) = ob_req(i) - x;  ob(i) = ob(i) - x;
                ob_req_total = ob_req_total - x;  ob_total = ob_total - x;
                req_sent(i) = req_sent(i) + x;
                budget = budget - x;  sent = sent + x;
            end
            i = i + 1;
        end
        dl_raw(k) = sent;

        % retention: delete raw older than ret
        while hk_head <= k && se(hk_head) + ret <= b
            exp_unreq(k) = exp_unreq(k) + hk(hk_head);
            hk_total = hk_total - hk(hk_head);  hk(hk_head) = 0;
            hk_head = hk_head + 1;
        end
        while obs_head < next_end && oe(obs_head) + ret <= b
            i = obs_head;
            exp_req(k)   = exp_req(k) + ob_req(i);
            exp_unreq(k) = exp_unreq(k) + ob(i) - ob_req(i);
            req_lost(i)  = ob_req(i);
            ob_total = ob_total - ob(i);  ob_req_total = ob_req_total - ob_req(i);
            ob(i) = 0;  ob_req(i) = 0;
            obs_head = obs_head + 1;
        end

        % capacity
        over = hk_total + ob_total + proc_q - cap;
        if over > 0
            i = obs_head;                     % 1) unrequested camera raw
            while over > 0 && i <= m && os(i) < b
                x = min(ob(i) - ob_req(i), over);
                ob(i) = ob(i) - x;  ob_total = ob_total - x;
                over = over - x;  evicted(k) = evicted(k) + x;
                i = i + 1;
            end
            while over > 0 && hk_head <= k    % 2) housekeeping raw
                x = min(hk(hk_head), over);
                hk(hk_head) = hk(hk_head) - x;  hk_total = hk_total - x;
                over = over - x;  evicted(k) = evicted(k) + x;
                if hk(hk_head) <= 0, hk_head = hk_head + 1; end
            end
            i = obs_head;                     % 3) requested camera raw
            while over > 0 && i < next_end
                x = min(ob_req(i), over);
                ob_req(i) = ob_req(i) - x;  ob(i) = ob(i) - x;
                ob_req_total = ob_req_total - x;  ob_total = ob_total - x;
                req_lost(i) = req_lost(i) + x;
                over = over - x;  evicted(k) = evicted(k) + x;
                i = i + 1;
            end
            if over > 0                       % 4) can't store new processed
                % Request-eligibility marks assume FIFO with no drops, so
                % they're approximate after this happens.
                x = min(proc_q, over);
                proc_q = proc_q - x;  cum_pg = cum_pg - x;
                dropped_proc(k) = x;
            end
        end

        st_hk(k) = hk_total;  st_cam(k) = ob_total - ob_req_total;
        st_req(k) = ob_req_total;  st_proc(k) = proc_q;
        pass_active(k) = pass_s > 0;  cam_active(k) = cam_s > 0;
    end

    TimeUTC = t0 + seconds(se);
    StorageBits = st_hk + st_cam + st_req + st_proc;
    log = table(TimeUTC, StorageBits, st_hk, st_cam, st_req, st_proc, ...
        gen_raw, gen_proc, dl_proc, dl_raw, exp_unreq, exp_req, evicted, ...
        dropped_proc, pass_active, cam_active, ...
        'VariableNames', {'TimeUTC','StorageBits','RawHKBits','RawCamBits', ...
        'RawRequestedBits','ProcQueueBits','GenRawBits','GenProcBits', ...
        'DownlinkProcBits','DownlinkRawBits','ExpiredBits', ...
        'ExpiredRequestedBits','EvictedBits','DroppedProcBits', ...
        'InUsablePass','CameraOn'});

    % ---- per-window summary
    was_req = req & (1:m)' < next_end;
    tol = 1;   % bits
    summary.n_windows = m;
    summary.n_requested = sum(was_req);
    summary.n_req_delivered = sum(was_req & req_sent >= req_target - tol);
    summary.n_req_lost = sum(was_req & req_lost > tol);
    summary.n_req_pending = summary.n_requested - summary.n_req_delivered ...
        - summary.n_req_lost;
    summary.req_bits_target = sum(req_target);
    summary.req_bits_sent = sum(req_sent);
    summary.proc_latency_s = proc_dl_t - oe;   % detection -> ground [s]
    summary.raw_request_ready_s = elig_t - oe; % detection -> request can be served
    summary.usable_pass_s = sum(max(0, min(pe, T) - max(ps, 0)));
end