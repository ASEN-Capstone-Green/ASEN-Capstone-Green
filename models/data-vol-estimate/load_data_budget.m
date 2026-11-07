function src = load_data_budget(xlsx_path, sheet_name)
% LOAD_DATA_BUDGET  Read the unified-packet rows of the Data Budget sheet.
%
%   src = load_data_budget("Data_Processing_Budget.xlsx")
%
% Returns a table with one row per unified packet (column "Unified Packet?"
% = TRUE) from both the "Data In" (raw, onboard) and "Data Out" (processed,
% downlink queue) blocks:
%
%   dir          "in" (raw, kept onboard for the retention period)
%                "out" (processed, queued for downlink)
%   subsystem, name, row (Excel row number)
%   packet_bits, rate_hz, duty, bits_per_day_sheet   (straight from sheet)
%   gate         when the sim generates it:
%                  "continuous"     - all the time
%                  "observation"    - only while the camera is on an object
%                  "pass"           - only during usable ground passes
%                  "perobservation" - one packet per object (at window end)
%   gate_duty    fraction of the gated time the packet is produced
%                (packets per object for "perobservation")
%
% The sheet's Duty Cycle column is a daily average, which the sim can't use
% directly for event-driven sources (the camera, commanding). Add two
% columns titled "Sim Gate" and "Gate Duty" to each block's header row to
% set these from the sheet; until then, defaults are inferred below.
%
% Reads the values Excel cached for each formula, so save the
% workbook in Excel after editing it.

    if nargin < 2
        sheet_name = "Data Budget";
    end

    C = readcell(xlsx_path, "Sheet", sheet_name);
    colA = strings(size(C,1),1);
    for r = 1:size(C,1)
        colA(r) = txt(C{r,1});
    end

    in_row  = find(colA == "Data In", 1);
    out_row = find(colA == "Data Out", 1);
    if isempty(in_row) || isempty(out_row)
        error("Could not find the 'Data In' / 'Data Out' blocks in column A.");
    end
    blocks = {"in", in_row, out_row - 1; "out", out_row, size(C,1)};

    rows = struct("dir",{},"subsystem",{},"name",{},"row",{}, ...
        "packet_bits",{},"rate_hz",{},"duty",{},"bits_per_day_sheet",{}, ...
        "gate",{},"gate_duty",{});
    used_defaults = false;

    for b = 1:size(blocks,1)
        dir = blocks{b,1};
        hdr_row = blocks{b,2} + 1;
        hdr = strings(1, size(C,2));
        for c = 1:size(C,2)
            hdr(c) = txt(C{hdr_row,c});
        end

        col.sub   = findcol(hdr, "Subsystem");
        col.uni   = findcol(hdr, "Unified");
        col.name  = findcol(hdr, "Short Name");
        col.pkt   = findcol(hdr, "Packet Size");
        col.rate  = findcol(hdr, "Rate (Hz)");
        col.duty  = findcol(hdr, "Duty Cycle");
        col.day   = findcol(hdr, "Data Gen");
        col.gate  = findcol(hdr, "Sim Gate", false);
        col.gduty = findcol(hdr, "Gate Duty", false);

        for r = hdr_row+1 : blocks{b,3}
            if ~istrue(C{r,col.uni}), continue; end
            pkt = num(C{r,col.pkt});
            if isnan(pkt), continue; end

            s.dir = string(dir);
            s.subsystem = txt(C{r,col.sub});
            s.name = txt(C{r,col.name});
            s.row = r;
            s.packet_bits = pkt;
            s.rate_hz = num(C{r,col.rate});
            s.duty = num(C{r,col.duty});
            s.bits_per_day_sheet = num(C{r,col.day});

            gate = "";
            gduty = NaN;
            if ~isempty(col.gate),  gate  = lower(erase(txt(C{r,col.gate})," ")); end
            if ~isempty(col.gduty), gduty = num(C{r,col.gduty}); end
            if gate == ""
                [gate, def_duty] = default_gate(s.dir, s.name, s.duty);
                if isnan(gduty), gduty = def_duty; end
                used_defaults = true;
            elseif isnan(gduty)
                gduty = 1;
            end
            if ~ismember(gate, ["continuous","observation","pass","perobservation"])
                error("Row %d (%s): unknown Sim Gate '%s'.", r, s.name, gate);
            end
            s.gate = gate;
            s.gate_duty = gduty;
            rows(end+1) = s; %#ok<AGROW>
        end
    end

    if used_defaults
        warning("load_data_budget:defaults", ...
            "No 'Sim Gate'/'Gate Duty' columns for some rows; using defaults in load_data_budget.m.");
    end
    src = struct2table(rows);
end

% ---------------------------------------------------------------------
function [gate, gduty] = default_gate(dir, name, duty)
% Fallback mapping for rows whose gate isn't set in the sheet.
    key = lower(strtrim(name));
    if dir == "in" && key == "payload packet"
        gate = "observation";    gduty = 1;
    elseif dir == "in" && key == "comms packet"
        gate = "pass";           gduty = 0.1;   % sheet: 10% of pass time
    elseif dir == "out" && key == "processed obj packet"
        gate = "perobservation"; gduty = 1;     % one packet per object
    elseif dir == "out" && key == "command acknowledgement packet"
        gate = "pass";           gduty = 0.01;  % sheet: 0.1 x command duty
    else
        gate = "continuous";
        gduty = duty;            % sheet's daily-average duty cycle
        if isnan(gduty), gduty = 1; end
    end
end

function c = findcol(hdr, pattern, required)
    if nargin < 3, required = true; end
    c = find(contains(hdr, pattern, "IgnoreCase", true), 1);
    if isempty(c) && required
        error("Header containing '%s' not found.", pattern);
    end
end

function s = txt(v)
    if ischar(v) || isstring(v)
        s = strtrim(string(v));
    else
        s = "";
    end
end

function x = num(v)
    if (isnumeric(v) || islogical(v)) && isscalar(v)
        x = double(v);
    else
        x = NaN;
    end
end

function tf = istrue(v)
    tf = (islogical(v) && isscalar(v) && v) || ...
         (isnumeric(v) && isscalar(v) && v == 1) || ...
         ((ischar(v) || isstring(v)) && strcmpi(strtrim(string(v)), "true"));
end