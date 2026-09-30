clear; clc; close all;

%% ============================================================
%  REPRESENTATIVE 1-10 CM SPACE DEBRIS SHELL
%
%  Monte Carlo debris environment:
%       10,000 simulated particles
%       1.5 million estimated physical objects
%       150 physical objects represented per simulated particle
%
%  Altitude:     600-1000 km
%  Inclination:  40-120 deg
%  RAAN:        -180 to +180 deg
%
%  Albedo cases:
%       Fragment = 0.20
%       MLI      = 0.56
%       NaK      = 0.85
%
%  All outputs are saved to the model-outputs folder under the
%  current working directory.
% ============================================================


%% OUTPUT FOLDER

relativeSaveFolder = './model-outputs';
saveFolder = fullfile(pwd,relativeSaveFolder);

if ~exist(saveFolder,'dir')
    mkdir(saveFolder);
end

rng(1);


%% ============================================================
%  MONTE CARLO SETTINGS
% ============================================================

Nparticles = 10000;

estimatedPopulation = 1.5e6;

objectsPerParticle = estimatedPopulation/Nparticles;
% 1,500,000 / 10,000 = 150 physical objects per MC particle


%% ============================================================
%  ALBEDO CASES
% ============================================================

% Representative PROOF albedo cases used in the ESA study:
%
% Fragment debris = 0.20
% MLI              = 0.56
% NaK droplets     = 0.85
%
% The ESA paper provides these representative albedo values.
% Equal probability between the three material classes is an
% assumption of this Monte Carlo model.

albedoValues = [0.20 0.56 0.85];

albedoNames = {
    'Fragment'
    'MLI'
    'NaK'
};

% Randomly assign one of the three material classes
albedoCase = randi(3,1,Nparticles);

albedo = albedoValues(albedoCase);


%% ============================================================
%  EARTH / ORBIT CONSTANTS
% ============================================================

Re = 6378e3;                 % Earth radius [m]

mu = 3.986004418e14;         % Earth gravitational parameter [m^3/s^2]


%% ============================================================
%  PROPAGATION SETTINGS
% ============================================================

dt = 30;                     % propagation timestep [s]

tEnd = 6000;                 % approximately one LEO orbit [s]

t = 0:dt:tEnd;

animationFrameStep = 2;

saveGIF = true;


%% ============================================================
%  ESA / MASTER ALTITUDE DISTRIBUTION
% ============================================================

debrisAltMin = 600e3;

debrisAltMax = 1000e3;


% 50 km altitude bins

debrisAltEdges = (600:50:1000)*1e3;


% Approximate relative debris concentration derived from the
% ESA / MASTER altitude distribution used for this trade study.

debrisDensity = [
    0.36
    0.52
    0.78
    1.00
    0.92
    0.73
    0.60
    0.50
];


% Normalize into probability weights

debrisWeights = debrisDensity/sum(debrisDensity);

debrisCDF = cumsum(debrisWeights);


%% ============================================================
%  ORBITAL ORIENTATION RANGE
% ============================================================

inclinationMin_deg = 40;

inclinationMax_deg = 120;


%% ============================================================
%  GENERATE DEBRIS ALTITUDES
% ============================================================

altitude = zeros(1,Nparticles);


for k = 1:Nparticles

    p = rand;

    bin = find(p <= debrisCDF,1,'first');

    lowerAlt = debrisAltEdges(bin);

    upperAlt = debrisAltEdges(bin+1);

    altitude(k) = ...
        lowerAlt + (upperAlt-lowerAlt)*rand;

end


%% ============================================================
%  GENERATE INCLINATIONS
% ============================================================

% The ESA paper supports the 40-120 degree inclination range,
% but does not provide an inclination probability-density curve.
%
% Therefore, this model distributes the particles evenly over
% the specified inclination range.

inclination_deg = linspace( ...
    inclinationMin_deg, ...
    inclinationMax_deg, ...
    Nparticles);


% Shuffle the values so inclination is not artificially
% correlated with altitude.

inclination_deg = ...
    inclination_deg(randperm(Nparticles));


inclination = deg2rad(inclination_deg);


%% ============================================================
%  GENERATE RAAN
% ============================================================

% Evenly distribute RAAN across the full 360 degrees.

RAAN_deg = linspace(-180,180,Nparticles+1);

RAAN_deg(end) = [];


% Shuffle to prevent artificial correlation with inclination.

RAAN_deg = RAAN_deg(randperm(Nparticles));

RAAN = deg2rad(RAAN_deg);


%% ============================================================
%  GENERATE INITIAL ORBITAL PHASE
% ============================================================

% Distribute particles around the full 360 degrees of their
% respective orbits.

phase0_deg = linspace(0,360,Nparticles+1);

phase0_deg(end) = [];


% Shuffle to prevent artificial alignment between orbital
% parameters.

phase0_deg = phase0_deg(randperm(Nparticles));

phase0 = deg2rad(phase0_deg);


%% ============================================================
%  CIRCULAR ORBIT PARAMETERS
% ============================================================

radius = Re + altitude;


% Mean motion for every debris particle

meanMotion = sqrt(mu./radius.^3);


%% ============================================================
%  ORBIT PLANE BASIS VECTORS
% ============================================================

P = [

    cos(RAAN)

    sin(RAAN)

    zeros(1,Nparticles)

];


Q = [

    -sin(RAAN).*cos(inclination)

     cos(RAAN).*cos(inclination)

     sin(inclination)

];


%% ============================================================
%  PRINT MODEL SUMMARY
% ============================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf('REPRESENTATIVE 1-10 CM DEBRIS SHELL\n');
fprintf('============================================================\n');

fprintf('Monte Carlo particles: %d\n',Nparticles);

fprintf('Estimated physical population: %.2f million\n', ...
    estimatedPopulation/1e6);

fprintf('Physical objects represented per particle: %.0f\n', ...
    objectsPerParticle);

fprintf('Altitude range: %.0f-%.0f km\n', ...
    debrisAltMin/1000, ...
    debrisAltMax/1000);

fprintf('Inclination range: %.0f-%.0f deg\n', ...
    inclinationMin_deg, ...
    inclinationMax_deg);

fprintf('RAAN range: -180 to +180 deg\n');

fprintf('Orbital phase range: 0 to 360 deg\n');

fprintf('\n');

fprintf('Altitude sampling: ESA/MASTER weighted\n');

fprintf('Inclination sampling: evenly distributed\n');

fprintf('RAAN sampling: evenly distributed\n');

fprintf('Phase sampling: evenly distributed\n');

fprintf('Albedo assignment: equal probability between\n');

fprintf('  Fragment = 0.20\n');
fprintf('  MLI      = 0.56\n');
fprintf('  NaK      = 0.85\n');

fprintf('============================================================\n');


%% ============================================================
%  MONTE CARLO ALTITUDE DISTRIBUTION
% ============================================================

figure(1);
clf;


binCenters_km = ...
    (debrisAltEdges(1:end-1) + ...
     debrisAltEdges(2:end))/(2*1000);


particleCounts = ...
    histcounts(altitude,debrisAltEdges);


estimatedObjectsByBin = ...
    particleCounts*objectsPerParticle;


plot( ...
    binCenters_km, ...
    estimatedObjectsByBin, ...
    '-o', ...
    'LineWidth',2);


grid on;


xlabel('Altitude [km]');

ylabel('Estimated Number of 1-10 cm Objects');

title('Monte Carlo 1-10 cm Debris Altitude Distribution');


distributionFile = fullfile( ...
    saveFolder, ...
    'Monte_Carlo_Debris_Distribution.png');


saveas(gcf,distributionFile);


%% ============================================================
%  INITIAL DEBRIS POSITIONS
% ============================================================

u = phase0;


r = radius .* ...
    (P.*cos(u) + Q.*sin(u));


%% EARTH SPHERE

[xEarth,yEarth,zEarth] = sphere(60);


%% ============================================================
%  INITIAL DEBRIS SHELL FIGURE
% ============================================================

figure(2);
clf;

hold on;
grid on;
axis equal;


surf( ...
    xEarth*Re/1000, ...
    yEarth*Re/1000, ...
    zEarth*Re/1000, ...
    'FaceAlpha',0.65, ...
    'EdgeColor','none');


scatter3( ...
    r(1,:)/1000, ...
    r(2,:)/1000, ...
    r(3,:)/1000, ...
    5, ...
    altitude/1000, ...
    'filled');


xlabel('ECI X [km]');

ylabel('ECI Y [km]');

zlabel('ECI Z [km]');


title({ ...
    'Representative 1-10 cm Orbital Debris Population', ...
    sprintf(['%d Monte Carlo particles representing ' ...
             'approximately %.1f million objects'], ...
             Nparticles, ...
             estimatedPopulation/1e6)});


cb = colorbar;

ylabel(cb,'Debris Altitude [km]');

clim([600 1000]);


view(35,25);


plotLimit = ...
    (Re + debrisAltMax + 250e3)/1000;


xlim([-plotLimit plotLimit]);

ylim([-plotLimit plotLimit]);

zlim([-plotLimit plotLimit]);


initialFigureFile = fullfile( ...
    saveFolder, ...
    'Debris_Shell_Initial.png');


saveas(gcf,initialFigureFile);


%% ============================================================
%  DEBRIS SHELL ANIMATION
% ============================================================

gifName = fullfile( ...
    saveFolder, ...
    'Debris_Shell_1cm_to_10cm.gif');


% Remove previous GIF so frames are not appended to an old run.

if exist(gifName,'file')

    delete(gifName);

end


fig = figure(3);

firstFrame = true;


fprintf('\nCreating debris shell animation...\n');

fprintf('Animation will be saved to:\n%s\n\n',gifName);


for ii = 1:animationFrameStep:length(t)


    %% CURRENT TIME

    currentTime = t(ii);


    %% PROPAGATE DEBRIS

    u = phase0 + ...
        meanMotion*currentTime;


    r = radius .* ...
        (P.*cos(u) + Q.*sin(u));


    %% CLEAR FRAME

    clf(fig);

    hold on;

    grid on;

    axis equal;


    %% EARTH

    surf( ...
        xEarth*Re/1000, ...
        yEarth*Re/1000, ...
        zEarth*Re/1000, ...
        'FaceAlpha',0.65, ...
        'EdgeColor','none');


    %% DEBRIS

    scatter3( ...
        r(1,:)/1000, ...
        r(2,:)/1000, ...
        r(3,:)/1000, ...
        5, ...
        altitude/1000, ...
        'filled');


    %% LABELS

    xlabel('ECI X [km]');

    ylabel('ECI Y [km]');

    zlabel('ECI Z [km]');


    title({ ...
        'Representative 1-10 cm Orbital Debris Population', ...
        sprintf(['Time = %.1f min | %d simulated particles | ' ...
                 '150 objects/particle | ~%.1f million total'], ...
                 currentTime/60, ...
                 Nparticles, ...
                 estimatedPopulation/1e6)});


    %% COLORBAR

    cb = colorbar;

    ylabel(cb,'Debris Altitude [km]');

    clim([600 1000]);


    %% AXIS LIMITS

    xlim([-plotLimit plotLimit]);

    ylim([-plotLimit plotLimit]);

    zlim([-plotLimit plotLimit]);


    view(35,25);

    drawnow;


    %% ========================================================
    %  WRITE GIF FRAME
    % ========================================================

    if saveGIF


        frame = getframe(fig);


        imageData = frame2im(frame);


        [indexedImage,colorMap] = ...
            rgb2ind(imageData,256);


        if firstFrame


            imwrite( ...
                indexedImage, ...
                colorMap, ...
                gifName, ...
                'gif', ...
                'LoopCount',inf, ...
                'DelayTime',0.08);


            firstFrame = false;


        else


            imwrite( ...
                indexedImage, ...
                colorMap, ...
                gifName, ...
                'gif', ...
                'WriteMode','append', ...
                'DelayTime',0.08);


        end

    end

end


%% ============================================================
%  CREATE REPRESENTATIVE POPULATION TABLE
% ============================================================

materialClass = albedoNames(albedoCase);

% Force material names into a column
materialClass = materialClass(:);

DebrisPopulation = table( ...
    (1:Nparticles).', ...
    altitude(:)/1000, ...
    inclination_deg(:), ...
    RAAN_deg(:), ...
    phase0_deg(:), ...
    albedo(:), ...
    materialClass, ...
    repmat(objectsPerParticle,Nparticles,1), ...
    'VariableNames',{ ...
    'Particle', ...
    'Altitude_km', ...
    'Inclination_deg', ...
    'RAAN_deg', ...
    'InitialPhase_deg', ...
    'Albedo', ...
    'MaterialClass', ...
    'ObjectsRepresented'});

%% ============================================================
%  SAVE POPULATION CSV
% ============================================================

populationCSV = fullfile( ...
    saveFolder, ...
    'Representative_Debris_Population.csv');


try

    writetable( ...
        DebrisPopulation, ...
        populationCSV);

catch ME

    warning( ...
        'Could not write CSV: %s', ...
        ME.message);

end


%% ============================================================
%  SAVE MODEL FOR CANT-ANGLE / LOCAL-DENSITY STUDY
% ============================================================

modelFile = fullfile( ...
    saveFolder, ...
    'Debris_Shell_Model.mat');


save( ...
    modelFile, ...
    'DebrisPopulation', ...
    'Nparticles', ...
    'altitude', ...
    'inclination_deg', ...
    'RAAN_deg', ...
    'phase0_deg', ...
    'debrisAltEdges', ...
    'debrisDensity', ...
    'debrisWeights', ...
    'albedo', ...
    'albedoCase', ...
    'albedoValues', ...
    'albedoNames', ...
    'estimatedPopulation', ...
    'objectsPerParticle', ...
    'Re', ...
    'mu');


%% ============================================================
%  FINAL SUMMARY
% ============================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf('SIMULATION COMPLETE\n');
fprintf('============================================================\n');

fprintf('Monte Carlo particles: %d\n',Nparticles);

fprintf('Physical objects represented per particle: %.0f\n', ...
    objectsPerParticle);

fprintf('Total represented population: %.0f\n', ...
    Nparticles*objectsPerParticle);

fprintf('\nFILES SAVED:\n');

fprintf('1. Debris shell animation:\n');
fprintf('   Debris_Shell_1cm_to_10cm.gif\n');

fprintf('\n2. Initial debris shell:\n');
fprintf('   Debris_Shell_Initial.png\n');

fprintf('\n3. Altitude distribution:\n');
fprintf('   Monte_Carlo_Debris_Distribution.png\n');

fprintf('\n4. Population data:\n');
fprintf('   Representative_Debris_Population.csv\n');

fprintf('\n5. MATLAB debris model:\n');
fprintf('   Debris_Shell_Model.mat\n');

fprintf('\nAll files saved to:\n%s\n',saveFolder);

fprintf('============================================================\n');