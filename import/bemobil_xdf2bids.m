function bemobil_xdf2bids(config, varargin)
% Wrapper for fieldtrip function "data2bids"
% specifically for converting multimodal .xdf files to BIDS 
%
% Inputs :
%   config [struct, with required fields filename, bids_target_folder, subject, eeg.stream_keywords
%
%       config.filename               = 'P:\...SPOT_rotation\0_source-data\vp-1'\vp-1_control_body.xdf'; % required
%       config.bids_target_folder     = 'P:\...SPOT_rotation\1_BIDS-data';                               % required
%       config.subject                = 1;                                  % required
%       config.session                = 'VR';                               % optional 
%       config.run                    = 1;                                  % optional
%       config.task                   = 'rotation';                         % optional 
% 
%       config.eeg.stream_name        = 'BrainVision';                      % required
%       config.eeg.chanloc            = 'P:\...SPOT_rotation\0_raw-data\vp-1'\vp-1.elc'; % optional
%       config.eeg.new_chans          = '';                                 % optional
%         
%       config.motion.streams{1}.stream_name        = 'rigidbody1'; 
%       config.motion.streams{1}.tracking_system    = 'HTCVive'; 
%       config.motion.streams{1}.tracked_points     = 'leftFoot'; 
%       config.motion.streams{2}.stream_name        = 'rigidbody2'; 
%       config.motion.streams{2}.tracking_system    = 'HTCVive'; 
%       config.motion.streams{2}.tracked_points     = 'rightFoot';
%       config.motion.streams{3}.stream_name        = 'rigidbody3'; 
%       config.motion.streams{3}.tracking_system    = 'phaseSpace'; 
%       config.motion.streams{3}.tracked_points     = {'leftFoot', 'rightFoot'}; 
%       config.motion.streams{3}.POS.unit           = 'vm'; % in case you want to use custom unit
%
%       config.physio.streams{1}.stream_name        = {'force1'};           % optional
%
%--------------------------------------------------------------------------
% Optional Inputs :
%       Provide optional inputs as key value pairs. See below for example
%       bemobil_xdf2bids(config, 'general_metadata', generalInfo); 
% 
%       general_metadata
%       participant_metadata
%       eeg_metadata
%       motion_metadata
%       physio_metadata
% 
% Authors : 
%       Sein Jeung (seinjeung@gmail.com) & Soeren Grothkopp (email)
%--------------------------------------------------------------------------

% add load_xdf to path 
ft_defaults
[filepath,~,~] = fileparts(which('ft_defaults'));
addpath(fullfile(filepath, 'external', 'xdf'))

%% 
%--------------------------------------------------------------------------
%                   Check import configuration 
%--------------------------------------------------------------------------

% check which modalities are included
%--------------------------------------------------------------------------
importEEG           = isfield(config, 'eeg');                               % assume EEG is always in 
importMotion        = isfield(config, 'motion');
importPhys          = isfield(config, 'phys');

if ~importEEG
    error('Importing scripts require the EEG stream to be there for event processing')
end

% check for mandatory fields 
%--------------------------------------------------------------------------
config = checkfield(config, 'filename', 'required', ''); 
config = checkfield(config, 'bids_target_folder', 'required', ''); 
config = checkfield(config, 'subject', 'required', ''); 
config.eeg = checkfield(config.eeg, 'stream_name', 'required', '');         % for now, the EEG stream has to be there for smooth processing 

% assign default values to optional fields
%--------------------------------------------------------------------------
config = checkfield(config, 'task', 'DefaultTask', 'DefaultTask');

% validate file name parts 
%--------------------------------------------------------------------------
pat = {' ' '_'};

if contains(config.task, pat)
    error('Task label MUST NOT contain space or underscore. Please change task label.')
end

if isfield(config, 'session')
    if contains(config.session, pat)
        error('Session label MUST NOT contain space or underscore. Please change task label.')
    end
end


% EEG-related fields
%--------------------------------------------------------------------------
if importEEG
    config.eeg = checkfield(config.eeg, 'stream_name', 'required', ''); 
end

% motion-related fields
%--------------------------------------------------------------------------
if importMotion
    
    config.motion = checkfield(config.motion, 'streams', 'required', '');
    
    for Si = 1:numel(config.motion.streams)
        config.motion.streams{Si} = checkfield(config.motion.streams{Si}, 'stream_name', 'required', '');
        config.motion.streams{Si} = checkfield(config.motion.streams{Si}, 'tracking_system', 'required', '');
        config.motion.streams{Si} = checkfield(config.motion.streams{Si}, 'tracked_points', 'required', '');
    end
    
    if isfield(config.motion, 'custom_function')
        if isempty(config.motion.custom_function)
            % functions that resolve dataset-specific problems
            motionCustom            = 'bemobil_bids_motionconvert';
        else
            motionCustom            = config.motion.custom_function;
        end
    else
        motionCustom = 'bemobil_bids_motionconvert'; 
    end
    
    % default channel types and units
    motion_type.POS.unit        = 'm'; 
    motion_type.ORNT.unit       = 'rad';
    motion_type.VEL.unit        = 'm/s';
    motion_type.ANGVEL.unit     = 'r/s';
    motion_type.ACC.unit        = 'm/s^2';
    motion_type.ANGACC.unit     = 'r/s^2';
    motion_type.MAGN.unit       = 'fm';
    motion_type.JNTANG.unit     = 'r';

end

% physio-related fields
%--------------------------------------------------------------------------
if importPhys
    
    config.phys = checkfield(config.phys, 'streams', 'required', '');
    
    for Si = 1:numel(config.phys.streams)
        config.phys.streams{Si} = checkfield(config.phys.streams{Si}, 'stream_name', 'required', '');
    end
    
    % no custom function for physio processing supported yet
    physioCustom        = 'bemobil_bids_physioconvert';

end


%% 
%--------------------------------------------------------------------------
%                           Check metadata 
%--------------------------------------------------------------------------
% find optional input arguments
for iVI = 1:2:numel(varargin)
    if strcmp(varargin{iVI}, 'general_metadata')
        generalInfo         = varargin{iVI+1};
    elseif strcmp(varargin{iVI}, 'participant_metadata')
        subjectInfo         = varargin{iVI+1};
    elseif strcmp(varargin{iVI}, 'motion_metadata')
        motionInfo          = varargin{iVI+1};
    elseif strcmp(varargin{iVI}, 'eeg_metadata')
        eegInfo             = varargin{iVI+1};
    elseif strcmp(varargin{iVI}, 'physio_metadata')
        physioInfo             = varargin{iVI+1};
    else
        warning('One of the optional inputs are not valid : please see help bemobil_xdf2bids')
    end
end

% check general metadata 
%--------------------------------------------------------------------------
if ~exist('generalInfo', 'var')
    
    warning('Optional input general_metadata was not entered - using default general metadata (NOT recommended for data sharing)')
    
    generalInfo = [];
    
    % root directory (where you want your bids data to be saved)
    generalInfo.bidsroot                                = fullfile(config.study_folder, config.bids_data_folder);
    
    % required for dataset_description.json
    generalInfo.dataset_description.Name                = 'Default task';
    generalInfo.dataset_description.BIDSVersion         = 'unofficial extension';
    
    % optional for dataset_description.json
    generalInfo.dataset_description.License             = 'n/a';
    generalInfo.dataset_description.Authors             = 'n/a';
    generalInfo.dataset_description.Acknowledgements    = 'n/a';
    generalInfo.dataset_description.Funding             = 'n/a';
    generalInfo.dataset_description.ReferencesAndLinks  = 'n/a';
    generalInfo.dataset_description.DatasetDOI          = 'n/a';
    
    % general information shared across modality specific json files
    generalInfo.InstitutionName                         = 'Technische Universitaet zu Berlin';
    generalInfo.InstitutionalDepartmentName             = 'Biological Psychology and Neuroergonomics';
    generalInfo.InstitutionAddress                      = 'Strasse des 17. Juni 135, 10623, Berlin, Germany';
    generalInfo.TaskDescription                         = 'Default task generated by bemobil bidstools- no metadata present';
    generalInfo.task                                    = config.bids_task_label;
    
end

cfg = generalInfo;


% check motion metadata
%--------------------------------------------------------------------------
if importMotion
    
    % check how many different tracking systems are specified
    for Si = 1:numel(config.motion.streams)
        streamNames{Si}     = config.motion.streams{Si}.stream_name;
        trackSysNames{Si}   = config.motion.streams{Si}.tracking_system;
        trackedPointNames{Si} = config.motion.streams{Si}.tracked_points; 
    end
    
    % get the (unique) tracking system names included in data
    trackSysInData   = unique(trackSysNames);
  
    % get all stream names corresponding to each tracking system
    for Si = 1:numel(trackSysInData)
        trackSysInds = find(strcmp(trackSysNames, trackSysInData{Si})); 
        streamsInData{Si}           = streamNames(trackSysInds);
        trackedPointsInData{Si}     = trackedPointNames(trackSysInds); 
    end
    
    % construct default info for tracking systems
    tracking_systems                                    = trackSysInData;
    
    for Ti = 1:numel(tracking_systems)
        defaultTrackingSystems.(tracking_systems{Ti}).Manufacturer                     = 'DefaultManufacturer';
        defaultTrackingSystems.(tracking_systems{Ti}).ManufacturersModelName           = 'DefaultModel';
        defaultTrackingSystems.(tracking_systems{Ti}).SamplingFrequencyNominal         = 'n/a'; %  If no nominal Fs exists, n/a entry returns 'n/a'. If it exists, n/a entry returns nominal Fs from motion stream.
    end
    
    
    if ~exist('motionInfo', 'var')
        
        warning('Optional input motion_metadata was not entered - using default metadata (NOT recommended for data sharing)')
        
        % motion specific fields in json
        motionInfo.motion = [];
        motionInfo.motion.RecordingType                     = 'continuous';
        
        % default tracking system information
        motionInfo.motion.TrackingSystems = defaultTrackingSystems;
        
        % coordinate system
        motionInfo.coordsystem.MotionCoordinateSystem      = 'RUF';
        motionInfo.coordsystem.MotionRotationRule          = 'left-hand';
        motionInfo.coordsystem.MotionRotationOrder         = 'ZXY';
        
    else
        if isfield(motionInfo, 'motion')
            if isfield(motionInfo.motion, 'TrackingSystems')
                
                % take all tracking systems defined in the metadata input
                trackSysInMeta = fieldnames(motionInfo.motion.TrackingSystems);
                
                % identify tracking systems in the data but not in metadata
                trackSysNoMeta  = setdiff(trackSysInData, trackSysInMeta);
                
                % construct metadata for ones that are missing them
                for Ti = 1:numel(trackSysNoMeta)
                    motionInfo.motion.TrackingSystems.(trackSysNoMeta{Ti}).Manufacturer                     = 'DefaultManufacturer';
                    motionInfo.motion.TrackingSystems.(trackSysNoMeta{Ti}).ManufacturerModelName            = 'DefaultModel';
                    motionInfo.motion.TrackingSystems.(trackSysNoMeta{Ti}).SamplingFrequencyNominal         = 'n/a';
                end
                
                % identify tracking systems in metadata but not in the data
                trackSysNoData = setdiff(trackSysInMeta, trackSysInData);
                
                % remove unused tracking systems from metadata struct
                motionInfo.motion.TrackingSystems = rmfield(motionInfo.motion.TrackingSystems, trackSysNoData);
            else
                warning('No information on tracking system given - filling with default info')
                
                % default tracking system information
                motionInfo.motion.TrackingSystems = defaultTrackingSystems;
            end
        else
            warning('No information for motion json given - filling with default info')
            
            % motion specific fields in json
            motionInfo.motion.RecordingType                     = 'continuous';
            
            % default tracking system information
            motionInfo.motion.TrackingSystems = defaultTrackingSystems;
        end        
    end
    
    % create key value maps for tracking systems and stream names
    kv_trsys_to_st          = containers.Map(trackSysInData, streamsInData);
    kv_trsys_to_trp         = containers.Map(trackSysInData, trackedPointsInData); 
    
end


%% 
% check if the output is already in BIDS folder
%--------------------------------------------------------------------------
% if importMotion
%     if exist(pDir, 'dir')
%         disp(['BIDS file ' pDir ' exists. Files may be overwritten'])
%     end
% end

% wasImported = sum(wasimported);

% check if numerical IDs match subject info, if this was specified
%--------------------------------------------------------------------------
if exist('subjectInfo','var')
    
    nrColInd                = find(strcmp(subjectInfo.cols, 'nr'));
    
    % attempt to find matching rows in subject info
    pRowInd          = find(cell2mat(subjectInfo.data(:,nrColInd)) == config.subject,1);
    if isempty(pRowInd)
        warning(['Participant ' num2str(numericalIDs(Pi)) ' info not given : filling with n/a'])
        emptyRow         = {config.subject};
        [emptyRow{2:size(subjectInfo.data,2)}] = deal('n/a');
        newPInfo   = emptyRow;
    else
        newPInfo   = subjectInfo.data(pRowInd,:);
    end
    
else
    warning('Optional input participant_metadata was not entered - participant.tsv will be omitted (NOT recommended for data sharing)')
end

%--------------------------------------------------------------------------
% determine number of days for shifting acq_time
shift = randi([-1000,1000]);

% construct file and participant- and file- specific config
% information needed to construct file paths and names
%--------------------------------------------------------------------------
cfg.sub                                     = num2str(config.subject);
cfg.dataset                                 = config.filename; 
cfg.bidsroot                                = config.bids_target_folder; 
cfg.participants                            = []; 

if isfield(config, 'session')
    cfg.ses                                     = config.session;
end
if isfield(config, 'run')
    cfg.run                                     = config.run;
end

% participant information
if exist('subjectInfo', 'var')
    
    allColumns      = subjectInfo.cols;
    
    % find the index of the subject nr column
    for iCol = 1:numel(allColumns)
        if strcmp(subjectInfo.cols(iCol), 'nr')
            nrColInd = iCol; 
        end
    end
    
    if ~exist('nrColInd','var')
        error('Participant info was provided without column "nr".')
    end
    
    % find the column that contains information from the given participant
    Pi = find([subjectInfo.data{:,nrColInd}] == config.subject); % find the matching participant number
    
    for iCol = 1:numel(allColumns)
            cfg.participants.(allColumns{iCol}) = subjectInfo.data{Pi, iCol};
    end
    
end

%% 
% load and assign streams (parts taken from xdf2fieldtrip)
%--------------------------------------------------------------------------
streams                  = load_xdf(cfg.dataset);

% initialize an array of booleans indicating whether the streams are continuous
iscontinuous = false(size(streams));

names = {};

% figure out which streams contain continuous/regular and discrete/irregular data
for i=1:numel(streams)
    
    names{i}           = streams{i}.info.name;
    
    % if the nominal srate is non-zero, the stream is considered continuous
    if ~strcmpi(streams{i}.info.nominal_srate, '0')
        
        iscontinuous(i) =  true;
        num_samples  = numel(streams{i}.time_stamps);
        t_begin      = streams{i}.time_stamps(1);
        t_end        = streams{i}.time_stamps(end);
        duration     = t_end - t_begin;
        
        if ~isfield(streams{i}.info, 'effective_srate')
            % in case effective srate field is missing, add one
            streams{i}.info.effective_srate = (num_samples - 1) / duration;
        elseif isempty(streams{i}.info.effective_srate)
            % in case effective srate field value is missing, add one
            streams{i}.info.effective_srate = (num_samples - 1) / duration;
        end
        
    else
        try
            num_samples  = numel(streams{i}.time_stamps);
            t_begin      = streams{i}.time_stamps(1);
            t_end        = streams{i}.time_stamps(end);
            duration     = t_end - t_begin;
            
            % if sampling rate is higher than 20 Hz,
            % the stream is considered continuous
            if (num_samples - 1) / duration >= 20
                iscontinuous(i) =  true;
                if ~isfield(streams{i}.info, 'effective_srate')
                    % in case effective srate field is missing, add one
                    streams{i}.info.effective_srate = (num_samples - 1) / duration;
                elseif isempty(streams{i}.info.effective_srate)
                    % in case effective srate field value is missing, add one
                    streams{i}.info.effective_srate = (num_samples - 1) / duration;
                end
            end
        catch
        end
    end
    
end

if importEEG
    eegStreamName = config.eeg.stream_name; 
    xdfeeg        = streams(contains(lower(names),lower(eegStreamName)) & iscontinuous);
    
    if isempty(xdfeeg)
        error('No eeg streams found - check whether stream_name match the names of streams in .xdf')
    end
end

if importMotion
    for Si = 1:numel(config.motion.streams) 
        motionStreamNames{Si}   = config.motion.streams{Si}.stream_name;
    end
    xdfmotion   = streams(contains(lower(names),lower(motionStreamNames)) & iscontinuous);
    
    if isempty(xdfmotion)
        error('Configuration field motion specified but no streams found - check whether stream_name match the names of streams in .xdf')
    end

end

if importPhys
    for Si = 1:numel(config.phys.streams)
        physioStreamNames{Si}   = config.phys.streams{Si}.stream_name;
    end
    xdfphysio   = streams(contains(lower(names),lower(physioStreamNames)) & iscontinuous);
    
    if isempty(xdfphysio)
        error('Configuration field physio specified but no streams found - check whether stream_name match the names of streams in .xdf')
    end
end

xdfmarkers  = streams(~iscontinuous);

%%
if importEEG % This loop is always executed in current version
    
    %----------------------------------------------------------------------
    %                   Convert EEG Data to BIDS
    %----------------------------------------------------------------------
    % construct fieldtrip data
    eeg        = stream2ft(xdfeeg{1});
    
    % save eeg start time
    eegStartTime                = eeg.time{1}(1);
    
    % eeg metadata construction
    %----------------------------------------------------------------------
    eegcfg                              = cfg;
    eegcfg.datatype                     = 'eeg';
    eegcfg.method                       = 'convert';
    
    if isfield(config.eeg, 'chanloc')
        if ~isempty(config.eeg.chanloc)
            eegcfg.coordsystem.EEGCoordinateSystem      = 'n/a';
            eegcfg.coordsystem.EEGCoordinateUnits       = 'mm';
        end
    end
    
    % try to extract information from config struct if specified
    if isfield(config.eeg, 'ref_channel')
        eegcfg.eeg.EEGReference                 = config.ref_channel;
    end
    
    if isfield(config.eeg, 'linefreqs')
        if numel(config.linefreqs) == 1
            eegcfg.eeg.PowerLineFrequency           = config.linefreqs;
        elseif numel(config.linefreqs) > 1
            eegcfg.eeg.PowerLineFrequency           = config.linefreqs(1);
            warning('Only the first value specified in config.eeg.linefreqs entered in eeg.json')
        end
    end
    
    % overwrite some fields if specified
    if exist('eegInfo','var')
        if isfield(eegInfo, 'eeg')
            eegcfg.eeg          = eegInfo.eeg;
        end
        if isfield(eegInfo, 'coordsystem')
            eegcfg.coordsystem  = eegInfo.coordsystem;
        end
    end
    
    
    % read in the event stream (synched to the EEG stream)
    if ~isempty(xdfmarkers)
        
        if any(cellfun(@(x) ~isempty(x.time_series), xdfmarkers))
            
            events                  = stream2events(xdfmarkers, xdfeeg{1}.time_stamps);
            eventsFound             = 1;
            
            % event parser script
            if isfield(config, 'bids_parsemarkers_custom')
                if isempty(config.bids_parsemarkers_custom)
                    [events, eventsJSON] = bemobil_bids_parsemarkers(events);
                else
                    [events, eventsJSON] = feval(config.bids_parsemarkers_custom, events);
                end
            else 
                [events, eventsJSON] = bemobil_bids_parsemarkers(events);
            end
            
            eegcfg.events = events;
            
        end
    end
    
    if isfield(config.eeg, 'elec_struct')
        eegcfg.elec                         = config.elec_struct;
    elseif isfield(config.eeg, 'chanloc')
        eegcfg.elec = config.eeg.chanloc;
    end
    
    % shift acq_time and look for missing acquisition time data
    if ~isfield(cfg, 'acq_times')
        warning(' acquisition times are not defined. Unable to display acq_time for eeg data.')
    elseif isempty(cfg.acq_times)
        warning(' acquisition times are not specified. Unable to display acq_time for eeg data.')
    else
        acq_time = cfg.acq_times{pi,si};
        acq_time([1:4]) = num2str(config.bids_shift_acquisition_time);
        eegcfg.acq_time = datestr(datenum(acq_time) + shift,'yyyy-mm-ddTHH:MM:SS.FFF'); % microseconds are rounded
    end
    
    % write eeg files in bids format
    data2bids(eegcfg, eeg);
    
end

%%
if importMotion
    
    %----------------------------------------------------------------------
    %                   Convert Motion Data to BIDS
    %----------------------------------------------------------------------
    ftmotion = {};
    
    % construct fieldtrip data
    for iM = 1:numel(xdfmotion)
        ftmotion{iM} = stream2ft(xdfmotion{iM});
    end
    
    MotionChannelCount = 0;
    TrackedPointsCountTotal = 0;
    
    for tsi = 1:numel(trackSysInData)
        
        motionStreamNames   = kv_trsys_to_st(trackSysInData{tsi});
        trackedPointNames   = kv_trsys_to_trp(trackSysInData{tsi}); 
        
        if isfield(cfg, 'ses')
            si = cfg.ses;
        else
            si = 1;
        end
        if isfield(cfg, 'run')
            ri = cfg.run;
        else
            ri = 1;
        end
        
        streamInds = [];
        for Fi = 1:numel(ftmotion)
           if contains(lower(ftmotion{Fi}.hdr.orig.name),lower(motionStreamNames))
               streamInds(end+1) = Fi; 
           end
        end
        
        % if needed, execute a custom function for any alteration to the data to address dataset specific issues
        % (quat2eul conversion, unwrapping of angles, resampling, wrapping back to [pi, -pi], and concatenating for instance)
        motion = feval(motionCustom, ftmotion(streamInds), trackedPointNames, config.subject, si, ri);
        
        % save motion start time
        motionStartTime              = motion.time{1}(1);
        
        % loop over files in each session.
        % Here 'di' will index files as runs.
        for di = 1:numel(sortedFileNames)
            
            motionStreamNames                       = bemobil_config.rigidbody_streams; % reset after modified for multisystem use 
            
            
            % construct file and participant- and file- specific config
            % information needed to construct file paths and names
            cfg.sub                                     = num2str(participantNr,'%03.f');
            cfg.dataset                                 = fullfile(participantDir, sortedFileNames{di}); % tells loadxdf where to find dataset
            cfg.ses                                     = bemobil_config.session_names{si};
            cfg.run                                     = di;
            cfg.tracksys                                = [];


            % remove session label in uni-session case
            if numel(bemobil_config.session_names) == 1
                cfg = rmfield(cfg, 'ses');
            end

            % remove session label in uni-run case
            if numel(sortedFileNames) == 1
                cfg = rmfield(cfg, 'run');
            end

            % participant information
            if exist('subjectInfo', 'var')
                allColumns      = subjectInfo.cols;
                for iCol = 1:numel(allColumns)
                    if ~strcmp(allColumns{iCol},'nr')
                        cfg.participants.(allColumns{iCol}) = subjectInfo.data{pi, iCol};
                    end
                end
            end
            

            % load and assign streams (parts taken from xdf2fieldtrip)
            %--------------------------------------------------------------
            streams                  = load_xdf(cfg.dataset);

            % initialize an array of booleans indicating whether the streams are continuous
            iscontinuous = false(size(streams));

            names = {};

            % figure out which streams contain continuous/regular and discrete/irregular data
            for i=1:numel(streams)

                names{i}           = streams{i}.info.name;

                % if the nominal srate is non-zero, the stream is considered continuous
                if ~strcmpi(streams{i}.info.nominal_srate, '0')

                    iscontinuous(i) =  true;
                    num_samples  = numel(streams{i}.time_stamps);
                    t_begin      = streams{i}.time_stamps(1);
                    t_end        = streams{i}.time_stamps(end);
                    duration     = t_end - t_begin;

                    if ~isfield(streams{i}.info, 'effective_srate')
                        % in case effective srate field is missing, add one
                        streams{i}.info.effective_srate = (num_samples - 1) / duration;
                    elseif isempty(streams{i}.info.effective_srate)
                        % in case effective srate field value is missing, add one
                        streams{i}.info.effective_srate = (num_samples - 1) / duration;
                    end

                else
                    try
                        num_samples  = numel(streams{i}.time_stamps);
                        t_begin      = streams{i}.time_stamps(1);
                        t_end        = streams{i}.time_stamps(end);
                        duration     = t_end - t_begin;

                        % if sampling rate is higher than 20 Hz,
                        % the stream is considered continuous
                        if (num_samples - 1) / duration >= 20
                            iscontinuous(i) =  true;
                            if ~isfield(streams{i}.info, 'effective_srate')
                                % in case effective srate field is missing, add one
                                streams{i}.info.effective_srate = (num_samples - 1) / duration;
                            elseif isempty(streams{i}.info.effective_srate)
                                % in case effective srate field value is missing, add one
                                streams{i}.info.effective_srate = (num_samples - 1) / duration;
                            end
                        end
                    catch
                    end
                end

            end

            xdfeeg      = streams(contains(names,eegStreamName) & iscontinuous);
            xdfmotion   = streams(contains(names,motionStreamNames(bemobil_config.bids_rb_in_sessions(si,:))) & iscontinuous);
            xdfphysio   = streams(contains(names,physioStreamNames(bemobil_config.bids_phys_in_sessions(si,:))) & iscontinuous);
            xdfmarkers  = streams(~iscontinuous);

            %--------------------------------------------------------------
            %                  Convert EEG Data to BIDS
            %--------------------------------------------------------------
            % construct fieldtrip data
            eeg        = stream2ft(xdfeeg{1});

            % save eeg start time
            eegStartTime                = eeg.time{1}(1);

            % eeg metadata construction
            %--------------------------------------------------------------
            eegcfg                              = cfg;
            eegcfg.datatype                     = 'eeg';
            eegcfg.method                       = 'convert';

            if ~isempty(bemobil_config.channel_locations_filename)
                eegcfg.coordsystem.EEGCoordinateSystem      = 'n/a';
                eegcfg.coordsystem.EEGCoordinateUnits       = 'mm';
            end

            % try to extract information from config struct if specified
            if isfield(bemobil_config, 'ref_channel')
                eegcfg.eeg.EEGReference                 = bemobil_config.ref_channel;
            end

            if isfield(bemobil_config, 'linefreqs')
                if numel(bemobil_config.linefreqs) == 1
                    eegcfg.eeg.PowerLineFrequency           = bemobil_config.linefreqs;
                elseif numel(bemobil_config.linefreqs) > 1
                    eegcfg.eeg.PowerLineFrequency           = bemobil_config.linefreqs(1);
                    warning('Only the first value specified in bemobil_config.linefreqs entered in eeg.json')
                end
            end

            % overwrite some fields if specified
            if exist('eegInfo','var')
                if isfield(eegInfo, 'eeg')
                    eegcfg.eeg          = eegInfo.eeg;
                end
                if isfield(eegInfo, 'coordsystem')
                    eegcfg.coordsystem  = eegInfo.coordsystem;
                end
            end
            

            % read in the event stream (synched to the EEG stream)
            if ~isempty(xdfmarkers)

                if any(cellfun(@(x) ~isempty(x.time_series), xdfmarkers))

                    events                  = stream2events(xdfmarkers, xdfeeg{1}.time_stamps);
                    eventsFound             = 1;

                    % event parser script
                    if isempty(bemobil_config.bids_parsemarkers_custom)
                        [events, eventsJSON] = bemobil_bids_parsemarkers(events);
                    else
                        [events, eventsJSON] = feval(bemobil_config.bids_parsemarkers_custom, events);
                    end

                    eegcfg.events = events;

                end
            end

            if isfield(bemobil_config, 'elec_struct')
                eegcfg.elec                         = bemobil_config.elec_struct;
            elseif isfield(bemobil_config, 'channel_locations_filename')
                eegcfg.elec = fullfile(participantDir, [bemobil_config.filename_prefix, num2str(participantNr) '_' bemobil_config.channel_locations_filename]);
            end
           
            % shift acq_time and look for missing acquisition time data
            if ~isfield(cfg, 'acq_times')
                warning(' acquisition times are not defined. Unable to display acq_time for eeg data.')
            elseif isempty(cfg.acq_times)
                warning(' acquisition times are not specified. Unable to display acq_time for eeg data.')
            else             
                acq_time = cfg.acq_times{pi,si};  
                acq_time([1:4]) = num2str(bemobil_config.bids_shift_acquisition_time);
                eegcfg.acq_time = datestr(datenum(acq_time) + shift,'yyyy-mm-ddTHH:MM:SS.FFF'); % microseconds are rounded
            end
            
            % write eeg files in bids format
            data2bids(eegcfg, eeg);
        
            for Ti = 1:numel(bemobil_config.other_data_types)

                switch bemobil_config.other_data_types{Ti}

                    case 'motion'
                        %--------------------------------------------------
                        %            Convert Motion Data to BIDS
                        %--------------------------------------------------
                        
                        % check for missing or wrong trackingsystem information
                        if ~isfield(motionInfo.motion , 'trsystems')
                            error('Trackingsystems must be specified. Please create motionInfo.motion.trsystems containing names of tracking systems.') 
                        elseif isempty(motionInfo.motion.trsystems)
                            error('Trackingsystems must be specified. Please enter name of tracking systems in motionInfo.motion.trsystems .') 
                        else 
                            if any(contains(motionInfo.motion.trsystems, '_'))
                                error('Name of trackingsystem MUST NOT contain underscores. Please change name of trackingsystem.')
                            end
                        end
                        
                        % check if any motion data was found at all
                        if isempty(xdfmotion)
                            continue;
                        end

                        ftmotion = {};

                        % construct fieldtrip data
                        for iM = 1:numel(xdfmotion)
                            ftmotion{iM} = stream2ft(xdfmotion{iM});
                        end
                        
                        % tracksys in session
                        trsystems                       = motionInfo.motion.trsystems;
                        trsystems_in_session            = trsystems(motionInfo.motion.tracksys_in_session(si,:));  
                                              
                        % order fieldtrip data according to tracksys
                        rb_prefix_in_session = motionInfo.motion.rb_prefix(motionInfo.motion.tracksys_in_session(si,:));
                        
                        idx_ftmotion =[];
                        for iP = 1:numel(rb_prefix_in_session)
                            has_prefix = [];
                            for iM = 1:numel(ftmotion)
                                has_prefix(iM) = any(contains(ftmotion{iM}.label,rb_prefix_in_session{iP}));
                            end
                            idx_ftmotion = [idx_ftmotion find(has_prefix)];
                        end
                        
                        ftmotion = ftmotion(idx_ftmotion);
                        
                        %--------------------------------------------------
                        % determine use case
                        
                        multisys = false;
                        singlesys = false;
                        singlestream = false;
                        
                        if numel(trsystems_in_session) > 1
                            multisys = true;
                        else
                            singlesys = true;
                        end 
                        
                        if any(contains(rb_prefix_in_session,bemobil_config.rb_prefix_single_stream ))
                           singlestream = true;
                        end 
                        %--------------------------------------------------
                        % Preparing data for singlestream and multisys/singlesys case
                        if singlestream
                            
                            % checks
                            if ~isfield(bemobil_config, 'rigidbody_single_stream_names')
                                error('bemobil_config.rigidbody_single_stream_names must exist')
                            elseif isempty(bemobil_config.rigidbody_single_stream_names)
                                error('bemobil_config.rigidbody_single_stream_names must contain entries')
                            end

                            single_stream_rb_names = bemobil_config.rigidbody_single_stream_names;
                            
                            for rbi = 1:numel(bemobil_config.rb_prefix_single_stream)
                                
                                % find single stream
                                has_single_stream = [];
                                idx_single_stream = [];

                                for fti = 1:numel(ftmotion)
                                    has_single_stream(fti) = any(contains(ftmotion{fti}.label,bemobil_config.rb_prefix_single_stream{rbi}));
                                end 
                                
                                idx_single_stream = find(has_single_stream);

                                % add new motion stream names
                                motionStreamNames = motionStreamNames(bemobil_config.bids_rb_in_sessions(si,:));
                                motionStreamNames(idx_single_stream) = [];
                                
                                idx_rb_names = [];
                                idx_rb_names = find(contains(single_stream_rb_names, ...
                                    bemobil_config.rb_prefix_single_stream(rbi))); 
                                
                                % append rb names from single stream
                                motionStreamNames_in_session = [motionStreamNames single_stream_rb_names(idx_rb_names)]; 
                                
                                % check rb of single stream in session
                                if ~isfield(bemobil_config, 'bids_rb_single_stream_in_sessions')
                                    warning('bids_rb_single_stream_in_sessions not defined. Assuming all rigidbodies are present in all sessions')
                                    bemobil_config.bids_rb_single_stream_in_sessions    = true(numel(bemobil_config.session_names),numel(motionStreamNames));
                                else
                                    if ~islogical(bemobil_config.bids_rb_single_stream_in_sessions)
                                        bemobil_config.bids_rb_single_stream_in_sessions = logical(bemobil_config.bids_rb_single_stream_in_sessions);
                                    end
                                end

                                % convert single stream rbs to streams
                                ftmotion_single_stream = [];
                                ftmotion_single_stream = extractRB(ftmotion{idx_single_stream},single_stream_rb_names(idx_rb_names));

                                % remove global single stream and replace with rb as streams
                                ftmotion{idx_single_stream} = ftmotion_single_stream;

                                % group rbs in cell according to tracksys
                                indices_single_stream(rbi)= idx_single_stream;

                                for iM = 1:numel(ftmotion)
                                    if iM~=indices_single_stream
                                        ftmotion{iM} = {ftmotion{iM}};
                                    end 
                                end 
                            end
                            
                            ftmotion_grouped = ftmotion;
                                
                            % group motionStreamNames in cell according to tracksys
                            for iP = 1:numel(rb_prefix_in_session)                           
                                idx_rb = find(contains(motionStreamNames_in_session,rb_prefix_in_session{iP}));
                                motionStreamNames_grouped{iP} = motionStreamNames_in_session(idx_rb);
                            end
                            
                            motionStreamNames = motionStreamNames_grouped;
                            
                        else % multisys or singlesys without single stream
                            
                            motionStreamNames_in_session = motionStreamNames(bemobil_config.bids_rb_in_sessions(si,:));
                            % group ftmotion and motionStreamNames in cell according to tracksys
                            for iP = 1:numel(rb_prefix_in_session)
                                % ftmotion
                                has_prefix = [];
                                for iM = 1:numel(ftmotion)
                                    has_prefix(iM) = any(contains(ftmotion{iM}.label,rb_prefix_in_session{iP}));
                                end
                                idx_ftmotion = find(has_prefix);
                                ftmotion_grouped{iP} = ftmotion(idx_ftmotion);
                                
                                % motionStreamNames
                                idx_rb = find(contains(motionStreamNames_in_session,rb_prefix_in_session{iP}));
                                motionStreamNames_grouped{iP} = motionStreamNames_in_session(idx_rb);
                            end
                            
%                             ftmotion = ftmotion_grouped; 
%                             motionStreamNames = motionStreamNames_grouped;

                        end 
                        

                        %--------------------------------------------------
                            if multisys
   
                                MotionChannelCount = 0; 
                                TrackedPointsCountTotal = 0;
                          
                                for tsi = 1:numel(trsystems_in_session)
                                    
                                    tracksys          = trsystems_in_session{tsi};
                                    ftmotion          = ftmotion_grouped{tsi};
                                    motionStreamNames = motionStreamNames_grouped{tsi};

                                    % if needed, execute a custom function for any alteration to the data to address dataset specific issues
                                    % (quat2eul conversion, unwrapping of angles, resampling, wrapping back to [pi, -pi], and concatenating for instance)
                                    motion = feval(motionCustom, ftmotion, motionStreamNames, participantNr, si, di);

                                    % save motion start time
                                    motionStartTime              = motion.time{1}(1);

                                    % construct motion metadata
                                    % copy general fields
                                    motioncfg       = cfg;
                                    motioncfg.datatype                                = 'motion';

                                    %--------------------------------------------------
                                    if ~exist('motionInfo', 'var')

                                        % data type and acquisition label
                                        motionInfo.acq                                     = 'Motion';

                                        % motion specific fields in json
                                        motionInfo.motion.Manufacturer                     = 'Undefined';
                                        motionInfo.motion.ManufacturersModelName           = 'Undefined';
                                        motionInfo.motion.RecordingType                    = 'continuous';

                                        % coordinate system
                                        motionInfo.coordsystem.MotionCoordinateSystem      = 'Undefined';
                                        motionInfo.coordsystem.MotionRotationRule          = 'Undefined';
                                        motionInfo.coordsystem.MotionRotationOrder         = 'Undefined';

                                    end

                                    motioncfg.TrackingSystemCount   = numel(trsystems_in_session);

                                    % sampling frequency
                                     if isfield(motion, 'fsample')
                                        motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyEffective = motion.fsample;
                                     else 
                                        motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyEffective = motion.hdr.Fs;
                                     end 

                                     if strcmpi(motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyNominal, 'n/a')
                                        motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyNominal = motion.hdr.nFs;
                                     end 

                                    % data type and acquisition label
                                    motioncfg.acq                                     = motionInfo.acq;

                                    % motion specific fields in json
                                    motioncfg.motion                                  = motionInfo.motion;

                                    % tracking system
                                    motioncfg.motion.trsystems                        = trsystems ; % needed for removing general trackingsys info 
                                    motioncfg.tracksys                                = tracksys; 
                                    motioncfg.motion.trsystems_in_session             = trsystems_in_session;

                                    % start time
                                    motioncfg.motion.start_time                       = motionStartTime - eegStartTime;

                                    % coordinate system
                                    motioncfg.coordsystem.MotionCoordinateSystem      = motionInfo.coordsystem.MotionCoordinateSystem;
                                    motioncfg.coordsystem.MotionRotationRule          = motionInfo.coordsystem.MotionRotationRule;
                                    motioncfg.coordsystem.MotionRotationOrder         = motionInfo.coordsystem.MotionRotationOrder;

                                    %--------------------------------------------------
                                    % rename and fill out motion-specific fields to be used in channels_tsv
                                    if singlestream
                                        rb_streams = horzcat(motionStreamNames_grouped{:}); 
                                        rb_names = bemobil_config.rigidbody_names(find(1 == bemobil_config.bids_rb_single_stream_in_sessions(si,:))); % usually rb in session would be used. Exception bc of how data is structured
                                        rb_anat = bemobil_config.rigidbody_anat(find(1 == bemobil_config.bids_rb_single_stream_in_sessions(si,:)));
                                    else
                                        rb_streams = bemobil_config.rigidbody_streams(find(1 == bemobil_config.bids_rb_in_sessions(si,:)));
                                        rb_names = bemobil_config.rigidbody_names(find(1 == bemobil_config.bids_rb_in_sessions(si,:)));
                                        rb_anat = bemobil_config.rigidbody_anat(find(1 == bemobil_config.bids_rb_in_sessions(si,:)));
                                    end


                                    motioncfg.channels.name                 = cell(motion.hdr.nChans,1);
                                    motioncfg.channels.tracked_point        = cell(motion.hdr.nChans,1);
                                    motioncfg.channels.component            = cell(motion.hdr.nChans,1);
                                    motioncfg.channels.placement            = cell(motion.hdr.nChans,1);
                                    motioncfg.channels.datafile             = cell(motion.hdr.nChans,1);

                                    for ci  = 1:motion.hdr.nChans

                                        if  contains(motion.hdr.chantype{ci},'position')
                                            motion.hdr.chantype{ci} = 'POS';
                                            motion.hdr.chanunit{ci} = bemobil_config.bids_motion_position_units{si};
                                        end

                                        if  contains(motion.hdr.chantype{ci},'orientation')
                                            motion.hdr.chantype{ci} = 'ORNT';
                                            motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                        end

                                        if  contains(motion.hdr.chantype{ci},'velocity')
                                            motion.hdr.chantype{ci} = 'VEL';
                                            motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                        end

                                        if  contains(motion.hdr.chantype{ci},'angularvelocity')
                                            motion.hdr.chantype{ci} = 'ANGVEL';
                                            motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                        end

                                        if  contains(motion.hdr.chantype{ci},'acceleration')
                                            motion.hdr.chantype{ci} = 'ACC';
                                            motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                        end

                                        if  contains(motion.hdr.chantype{ci},'angularacceleration')
                                            motion.hdr.chantype{ci} = 'ANGACC';
                                            motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                        end

                                        if  contains(motion.hdr.chantype{ci},'magneticfield')
                                            motion.hdr.chantype{ci} = 'MAGN';
                                            motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                        end

                                        if  contains(motion.hdr.chantype{ci},'jointangle')
                                            motion.hdr.chantype{ci} = 'JNTANG';
                                            motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                        end


                                        splitlabel                          = regexp(motion.hdr.label{ci}, '_', 'split');
                                        motioncfg.channels.name{ci}         = motion.hdr.label{ci};
                                        motioncfg.channels.tracking_system{ci}     = tracksys; 


                                        % assign object names and anatomical positions

                                        for iRB = 1:numel(rb_streams)
                                            if contains(motion.hdr.label{ci},rb_streams{iRB})
                                                motioncfg.channels.tracked_point{ci}       = rb_names{iRB};
                                                if iscell(bemobil_config.rigidbody_anat)
                                                    motioncfg.channels.placement{ci}  = rb_anat{iRB};
                                                else
                                                    motioncfg.channels.placement{ci} =  rb_anat;
                                                end
                                            end

                                        end

                                        motioncfg.channels.component{ci}    = splitlabel{end}; % REQUIRED. Component of the representational system that the channel contains.            
                                    end

                                     % shift acq_time and look for missing acquisition time data
                                     if ~isfield(cfg, 'acq_times')
                                        warning(' acquisition times are not defined. Unable to display acq_time for motion data.')
                                     elseif isempty(cfg.acq_times)
                                        warning(' acquisition times are not specified. Unable to display acq_time for motion data.')
                                     else
                                        acq_time = cfg.acq_times{pi,si};
                                        acq_time([1:4]) = num2str(bemobil_config.bids_shift_acquisition_time);
                                        acq_time = datenum(acq_time) - (motioncfg.motion.start_time/(24*60*60));
                                        motioncfg.acq_time = datestr(acq_time + shift,'yyyy-mm-ddTHH:MM:SS.FFF'); % microseconds are rounded 
                                     end 

                                    % RecordingDuration
                                    fs_effective = motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyEffective;
                                    motioncfg.motion.TrackingSystems.(tracksys).RecordingDuration = (motion.hdr.nSamples*motion.hdr.nTrials)/fs_effective;

                                    % tracked points per trackingsystem
                                    motioncfg.motion.tracksys = [];
                                    if checkequal(motionStreamNames) % checks if array contains similar entries
                                        warning(' rigidbody streams have the same name. Assuming TrackedPointsCount per trackingsystem is 1.')
                                        for ti=1:numel(motioncfg.motion.trsystems)
                                            tracksys = motioncfg.motion.trsystems{ti};
                                            motioncfg.motion.tracksys.(tracksys).TrackedPointsCount = 1; % hard coded TrackedPointsCount
                                        end 
                                    else
                                        for ti=1:numel(motioncfg.motion.trsystems)
                                            tracksys = motioncfg.motion.trsystems{ti};
                                            rb_name = kv_trsys_to_rb(tracksys); % select rigid body name corresponding to trackingsystem
                                            motioncfg.motion.tracksys.(tracksys).TrackedPointsCount = sum(contains(motionStreamNames, rb_name)); % add entries which contain rb_name for corresponding tracking system
                                        end 
                                    end 

                                    % match channel tokens with tracked points
                                    for tpi = 1:numel(bemobil_config.rigidbody_names)
                                        tokens{tpi} = ['t' num2str(tpi)];
                                    end 
                                    motioncfg.motion.tpPairs  = containers.Map(bemobil_config.rigidbody_names,tokens);

                                    % MotionChannelCount
                                    MotionChannelCount = MotionChannelCount + motion.hdr.nChans;
                                    motion.hdr.nChansTs = MotionChannelCount;

                                    % TrackedPointsCountTotal
                                    TrackedPointsCountTotal = TrackedPointsCountTotal + numel(unique(motioncfg.channels.tracked_point));
                                    motioncfg.motion.TrackedPointsCountTotal = TrackedPointsCountTotal;


                                    % write motion files in bids format
                                    data2bids(motioncfg, motion);

                                end 
                                
                            end 
                            
                            %--------------------------------------------------    
                            if singlesys
                                
                                tracksys          = trsystems_in_session{1};
                                ftmotion          = ftmotion_grouped{1};
                                motionStreamNames = motionStreamNames_grouped{1};
                                                              
                                % if needed, execute a custom function for any alteration to the data to address dataset specific issues
                                % (quat2eul conversion, unwrapping of angles, resampling, wrapping back to [pi, -pi], and concatenating for instance)
                                motion = feval(motionCustom, ftmotion, motionStreamNames, participantNr, si, di);

                                % save motion start time
                                motionStartTime              = motion.time{1}(1);

                                % construct motion metadata
                                % copy general fields
                                motioncfg       = cfg;
                                motioncfg.datatype                                = 'motion';

                                %--------------------------------------------------
                                if ~exist('motionInfo', 'var')

                                    % data type and acquisition label
                                    motionInfo.acq                                     = 'Motion';

                                    % motion specific fields in json
                                    motionInfo.motion.Manufacturer                     = 'Undefined';
                                    motionInfo.motion.ManufacturersModelName           = 'Undefined';
                                    motionInfo.motion.RecordingType                    = 'continuous';

                                    % coordinate system
                                    motionInfo.coordsystem.MotionCoordinateSystem      = 'Undefined';
                                    motionInfo.coordsystem.MotionRotationRule          = 'Undefined';
                                    motionInfo.coordsystem.MotionRotationOrder         = 'Undefined';

                                end

                                motioncfg.TrackingSystemCount   = numel(trsystems_in_session);

                                % sampling frequency
                                if isfield(motion, 'fsample')
                                   motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyEffective = motion.fsample;
                                else 
                                   motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyEffective = motion.hdr.Fs;
                                end 
                                
                                if strcmpi(motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyNominal, 'n/a')
                                   motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyNominal = motion.hdr.nFs;
                                end 


                                % data type and acquisition label
                                motioncfg.acq                                     = motionInfo.acq;

                                % motion specific fields in json
                                motioncfg.motion                                  = motionInfo.motion;

                                % tracking system
                                motioncfg.motion.trsystems                        = trsystems ; % needed for removing general trackingsys info 
                                motioncfg.tracksys                                = tracksys; % has to be adjusted for multiple tracking systems in one session
                                motioncfg.motion.trsystems_in_session             = trsystems_in_session;
                                
                                % start time
                                motioncfg.motion.start_time                       = motionStartTime - eegStartTime;

                                % coordinate system
                                motioncfg.coordsystem.MotionCoordinateSystem      = motionInfo.coordsystem.MotionCoordinateSystem;
                                motioncfg.coordsystem.MotionRotationRule          = motionInfo.coordsystem.MotionRotationRule;
                                motioncfg.coordsystem.MotionRotationOrder         = motionInfo.coordsystem.MotionRotationOrder;

                                %--------------------------------------------------
                                % rename and fill out motion-specific fields to be used in channels_tsv

                                if singlestream
                                    rb_streams = horzcat(motionStreamNames_grouped{:}); 
                                    rb_names = bemobil_config.rigidbody_names(find(1 == bemobil_config.bids_rb_single_stream_in_sessions(si,:))); % usually rb in session would be used. Exception bc of how data is structured
                                    rb_anat = bemobil_config.rigidbody_anat(find(1 == bemobil_config.bids_rb_single_stream_in_sessions(si,:)));
                                else
                                    rb_streams = bemobil_config.rigidbody_streams(find(1 == bemobil_config.bids_rb_in_sessions(si,:)));
                                    rb_names = bemobil_config.rigidbody_names(find(1 == bemobil_config.bids_rb_in_sessions(si,:)));
                                    rb_anat = bemobil_config.rigidbody_anat(find(1 == bemobil_config.bids_rb_in_sessions(si,:)));
                                end
                                
                                motioncfg.channels.name                 = cell(motion.hdr.nChans,1);
                                motioncfg.channels.tracked_point        = cell(motion.hdr.nChans,1);
                                motioncfg.channels.component            = cell(motion.hdr.nChans,1);
                                motioncfg.channels.placement            = cell(motion.hdr.nChans,1);
                                motioncfg.channels.datafile             = cell(motion.hdr.nChans,1);

                                for ci  = 1:motion.hdr.nChans

                                    if  contains(motion.hdr.chantype{ci},'position')
                                        motion.hdr.chantype{ci} = 'POS';
                                        motion.hdr.chanunit{ci} = bemobil_config.bids_motion_position_units{si};
                                    end

                                    if  contains(motion.hdr.chantype{ci},'orientation')
                                        motion.hdr.chantype{ci} = 'ORNT';
                                        motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                    end

                                    if  contains(motion.hdr.chantype{ci},'velocity')
                                        motion.hdr.chantype{ci} = 'VEL';
                                        motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                    end

                                    if  contains(motion.hdr.chantype{ci},'angularvelocity')
                                        motion.hdr.chantype{ci} = 'ANGVEL';
                                        motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                    end

                                    if  contains(motion.hdr.chantype{ci},'acceleration')
                                        motion.hdr.chantype{ci} = 'ACC';
                                        motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                    end

                                    if  contains(motion.hdr.chantype{ci},'angularacceleration')
                                        motion.hdr.chantype{ci} = 'ANGACC';
                                        motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                    end

                                    if  contains(motion.hdr.chantype{ci},'magneticfield')
                                        motion.hdr.chantype{ci} = 'MAGN';
                                        motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                    end

                                    if  contains(motion.hdr.chantype{ci},'jointangle')
                                        motion.hdr.chantype{ci} = 'JNTANG';
                                        motion.hdr.chanunit{ci} = bemobil_config.bids_motion_orientation_units{si};
                                    end


                                    splitlabel                          = regexp(motion.hdr.label{ci}, '_', 'split');
                                    motioncfg.channels.name{ci}         = motion.hdr.label{ci};
                                    motioncfg.channels.tracking_system{ci}     = motioncfg.tracksys; 


                                    % assign object names and anatomical positions
                                    for iRB = 1:numel(rb_streams)
                                        if contains(motion.hdr.label{ci}, rb_streams{iRB})
                                            motioncfg.channels.tracked_point{ci}       = rb_names{iRB};
                                            if iscell(bemobil_config.rigidbody_anat)
                                                motioncfg.channels.placement{ci}  = rb_anat{iRB};
                                            else
                                                motioncfg.channels.placement{ci} =  rb_anat;
                                            end
                                        end

                                    end

                                    motioncfg.channels.component{ci}    = splitlabel{end}; % REQUIRED. Component of the representational system that the channel contains.            
                                end



                                 % shift acq_time and look for missing acquisition time data
                                 if ~isfield(cfg, 'acq_times')
                                    warning(' acquisition times are not defined. Unable to display acq_time for motion data.')
                                 elseif isempty(cfg.acq_times)
                                    warning(' acquisition times are not specified. Unable to display acq_time for motion data.')
                                 else
                                    acq_time = cfg.acq_times{pi,si};
                                    acq_time([1:4]) = num2str(bemobil_config.bids_shift_acquisition_time);
                                    acq_time = datenum(acq_time) - (motioncfg.motion.start_time/(24*60*60));
                                    motioncfg.acq_time = datestr(acq_time + shift,'yyyy-mm-ddTHH:MM:SS.FFF'); % microseconds are rounded 
                                 end 
                                 
                                % RecordingDuration
                                fs_effective = motionInfo.motion.TrackingSystems.(tracksys).SamplingFrequencyEffective;
                                motioncfg.motion.TrackingSystems.(tracksys).RecordingDuration = (motion.hdr.nSamples*motion.hdr.nTrials)/fs_effective;
                                
                                % tracked points per trackingsystem
                                motioncfg.motion.tracksys = [];
                                if checkequal(motionStreamNames) % checks if array contains similar entries
                                    warning(' rigidbody streams have the same name. Assuming TrackedPointsCount per trackingsystem is 1.')
                                    for ti=1:numel(motioncfg.motion.trsystems)
                                        tracksys = motioncfg.motion.trsystems{ti};
                                        motioncfg.motion.tracksys.(tracksys).TrackedPointsCount = 1; % hard coded TrackedPointsCount
                                    end 
                                else
                                    for ti=1:numel(motioncfg.motion.trsystems)
                                        tracksys = motioncfg.motion.trsystems{ti};
                                        rb_name = kv_trsys_to_rb(tracksys); % select rigid body name corresponding to trackingsystem
                                        motioncfg.motion.tracksys.(tracksys).TrackedPointsCount = sum(contains(motionStreamNames, rb_name)); % add entries which contain rb_name for corresponding tracking system
                                    end 
                                end 

                                % match channel tokens with tracked points
                                for tpi = 1:numel(bemobil_config.rigidbody_names)
                                    tokens{tpi} = ['t' num2str(tpi)];
                                end 
                                motioncfg.motion.tpPairs  = containers.Map(bemobil_config.rigidbody_names,tokens);
                                
                                % MotionChannelCount
                                motion.hdr.nChansTs = motion.hdr.nChans;
                                
                                % TrackedPointCountTotal
                                motioncfg.motion.TrackedPointsCountTotal =  numel(unique(motioncfg.channels.tracked_point));
                                
                               
                                % write motion files in bids format
                                data2bids(motioncfg, motion);
                        end
                        
                    case 'physio'
                        %--------------------------------------------------
                        %         Convert Generic Physio Data to BIDS
                        %--------------------------------------------------
                        % check if any motion data was found at all
                        if isempty(xdfphysio)
                            continue;
                        end

                        ftphysio = {};

                        % construct fieldtrip data
                        for iP = 1:numel(xdfphysio)
                            ftphysio{iP} = stream2ft(xdfphysio{iP});
                        end

                        % resample data to match the stream of highest srate (no custom processing supported for physio data yet)
                        physio = feval(physioCustom, ftphysio, physioStreamNames(bemobil_config.bids_phys_in_sessions(si,:)), participantNr, si, di);

                        % save motion start time
                        physioStartTime              = physio.time{1}(1);

                        % construct motion metadata
                        % copy general fields
                        physiocfg               = cfg;
                        physiocfg.datatype      = 'physio';

                        %--------------------------------------------------------------
                        if ~exist('physioInfo', 'var')

                            % motion specific fields in json
                            physioInfo.physio.Manufacturer                     = 'Undefined';
                            physioInfo.physio.ManufacturersModelName           = 'Undefined';
                            physioInfo.physio.RecordingType                    = 'continuous';

                        end

                        % physio specific fields in json
                        physiocfg.physio                                  = physioInfo.physio;

                        % start time
                        physiocfg.physio.StartTime                        = physioStartTime - eegStartTime;

                        % write motion files in bids format
                        data2bids(physiocfg, physio);

                    otherwise
                        warning(['Unknown data type' bemobil_config.other_data_types{Ti}])
                end
            end
        end
    end
end


% add general json files
%--------------------------------------------------------------------------
ft_hastoolbox('jsonlab', 1);

if exist('subjectInfo', 'var')
    % participant.json
    pJSONName       = fullfile(cfg.bidsroot, 'participants.json');
    pfid            = fopen(pJSONName, 'wt');
    pString         = savejson('', subjectInfo.fields, 'NaN', '"n/a"', 'ParseLogical', true);
    fwrite(pfid, pString); fclose(pfid);
end

if eventsFound
    % events.json
    eJSONName       = fullfile(cfg.bidsroot, ['task-' cfg.task '_events.json']);
    efid            = fopen(eJSONName, 'wt');
    eString         = savejson('', eventsJSON, 'NaN', '"n/a"', 'ParseLogical', true);
    fwrite(efid, eString); fclose(efid);
end

end


%--------------------------------------------------------------------------
function [newconfig] =  checkfield(oldconfig, fieldName, defaultValue, defaultValueText)

newconfig   = oldconfig;

if ~isfield(oldconfig, fieldName)
    newconfig.(fieldName) = defaultValue;
    warning(['Config field ' fieldName ' not specified- using default value: ' defaultValueText])
end

end

%--------------------------------------------------------------------------
function [ftdata] = stream2ft(xdfstream)

% construct header
hdr.Fs                  = 'n/a';
hdr.Fs                  = xdfstream.info.effective_srate;
hdr.nFs                 = 'n/a';
hdr.nFs                 = str2num(xdfstream.info.nominal_srate);
hdr.nSamplesPre         = 0;
hdr.nSamples            = length(xdfstream.time_stamps);
hdr.nTrials             = 1;
hdr.FirstTimeStamp      = xdfstream.time_stamps(1);
hdr.TimeStampPerSample  = (xdfstream.time_stamps(end)-xdfstream.time_stamps(1)) / (length(xdfstream.time_stamps) - 1);
if isfield(xdfstream.info.desc, 'channels')
    hdr.nChans    = numel(xdfstream.info.desc.channels.channel);
else
    hdr.nChans    = str2double(xdfstream.info.channel_count);
end

hdr.label       = cell(hdr.nChans, 1);
hdr.chantype    = cell(hdr.nChans, 1);
hdr.chanunit    = cell(hdr.nChans, 1);

prefix = xdfstream.info.name;
for j=1:hdr.nChans
    if isfield(xdfstream.info.desc, 'channels')
        hdr.label{j} = [prefix '_' xdfstream.info.desc.channels.channel{j}.label];
        hdr.chantype{j} = xdfstream.info.desc.channels.channel{j}.type;
        try
            hdr.chanunit{j} = xdfstream.info.desc.channels.channel{j}.unit;
        catch
            disp([hdr.label{j} ' missing unit'])
        end
    else
        % the stream does not contain continuously sampled data
        hdr.label{j} = num2str(j);
        hdr.chantype{j} = 'unknown';
        hdr.chanunit{j} = 'unknown';
    end
end

% keep the original header details
hdr.orig = xdfstream.info;

ftdata.trial    = {xdfstream.time_series};
ftdata.time     = {xdfstream.time_stamps};
ftdata.hdr = hdr;
ftdata.label = hdr.label;

end

function outEvents = stream2events(inStreams, dataTimes)

outEvents = [];

for Si = 1:numel(inStreams)
    if iscell(inStreams{Si}.time_series)
        eventsInStream              = cell2struct(inStreams{Si}.time_series, 'value')';
        [eventsInStream.type]       = deal(inStreams{Si}.info.type);
        times                       = num2cell(inStreams{Si}.time_stamps);
        [eventsInStream.timestamp]  = times{:};
        samples                     = cellfun(@(x) find(dataTimes >= x, 1,'first'), times, 'UniformOutput', false);
        [eventsInStream.sample]     = samples{:};
        [eventsInStream.offset]     = deal([]);
        [eventsInStream.duration]   = deal([]);
        outEvents = [outEvents eventsInStream];
    end
end

% sort events by sample
[~,I] = sort([outEvents.timestamp]);
outEvents   = outEvents(I);

% re-order fields to match ft events output
outEvents   = orderfields(outEvents, [2,1,3,4,5,6]);

end


function newconfig = unit_check(oldconfig)

newconfig   = oldconfig;

% position
%-----------------------------------------------------------
    if isfield(oldconfig, 'bids_motion_position_units')
        if ~iscell(oldconfig.bids_motion_position_units)
            newconfig.bids_motion_position_units = {newconfig.bids_motion_position_units};
        end

        if numel(oldconfig.bids_motion_position_units) ~= numel(oldconfig.session_names)
            if numel(oldconfig.bids_motion_position_units) == 1
                newconfig.bids_motion_position_units = repmat(newconfig.bids_motion_position_units, 1, numel(oldconfig.session_names));
                warning('Only one pos unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_position_units must have either one entry or the number of entries (in cell array) have to match number of entries in field session_names')
            end
        end
    else
        newconfig.bids_motion_position_units       = repmat({'m'},1,numel(oldconfig.session_names));
        warning('Config field bids_motion_position_units unspecified - assuming meters')
    end
 
% orientation
%-----------------------------------------------------------
    if isfield(oldconfig, 'bids_motion_orientation_units')
        if ~iscell(oldconfig.bids_motion_orientation_units)
            newconfig.bids_motion_orientation_units = {newconfig.bids_motion_orientation_units};
        end

        if numel(oldconfig.bids_motion_orientation_units) ~= numel(oldconfig.session_names)
            if numel(oldconfig.bids_motion_orientation_units) == 1
                newconfig.bids_motion_orientation_units = repmat(newconfig.bids_motion_orientation_units, 1, numel(oldconfig.session_names));
                warning('Only one orientation unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_orientation_units must have either one entry or the number of entries (in cell array) have to match number of entries in field session_names')
            end
        end
    else
        newconfig.bids_motion_orientation_units       = repmat({'rad'},1,numel(oldconfig.session_names));
        warning('Config field bids_motion_orientation_units unspecified - assuming radians')
    end

% velocity
%-----------------------------------------------------------
    if isfield(oldconfig, 'bids_motion_velocity_units')
        if ~iscell(oldconfig.bids_motion_velocity_units)
            newconfig.bids_motion_velocity_units = {newconfig.bids_motion_velocity_units};
        end

        if numel(oldconfig.bids_motion_velocity_units) ~= numel(oldconfig.session_names)
            if numel(oldconfig.bids_motion_velocity_units) == 1
                newconfig.bids_motion_velocity_units = repmat(newconfig.bids_motion_velocity_units, 1, numel(oldconfig.session_names));
                warning('Only one orientation unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_velocity_units must have either one entry or the number of entries (in cell array) have to match number of entries in field session_names')
            end
        end
    else
        newconfig.bids_motion_velocity_units       = repmat({'m/s'},1,numel(oldconfig.session_names));
        warning('Config field bids_motion_velocity_units unspecified - assuming meters per second')
    end
    
% angularvelocity
%-----------------------------------------------------------
    if isfield(oldconfig, 'bids_motion_angularvelocity_units')
        if ~iscell(oldconfig.bids_motion_angularvelocity_units)
            newconfig.bids_motion_angularvelocity_units = {newconfig.bids_motion_angularvelocity_units};
        end

        if numel(oldconfig.bids_motion_angularvelocity_units) ~= numel(oldconfig.session_names)
            if numel(oldconfig.bids_motion_angularvelocity_units) == 1
                newconfig.bids_motion_angularvelocity_units = repmat(newconfig.bids_motion_angularvelocity_units, 1, numel(oldconfig.session_names));
                warning('Only one orientation unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_angularvelocity_units must have either one entry or the number of entries (in cell array) have to match number of entries in field session_names')
            end
        end
    else
        newconfig.bids_motion_angularvelocity_units       = repmat({'rad/s'},1,numel(oldconfig.session_names));
        warning('Config field bids_motion_angularvelocity_units unspecified - assuming radians per second')
    end
    
% acceleration
%-----------------------------------------------------------
    if isfield(oldconfig, 'bids_motion_acceleration_units')
        if ~iscell(oldconfig.bids_motion_acceleration_units)
            newconfig.bids_motion_acceleration_units = {newconfig.bids_motion_acceleration_units};
        end

        if numel(oldconfig.bids_motion_acceleration_units) ~= numel(oldconfig.session_names)
            if numel(oldconfig.bids_motion_acceleration_units) == 1
                newconfig.bids_motion_acceleration_units = repmat(newconfig.bids_motion_acceleration_units, 1, numel(oldconfig.session_names));
                warning('Only one orientation unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_acceleration_units must have either one entry or the number of entries (in cell array) have to match number of entries in field session_names')
            end
        end
    else
        newconfig.bids_motion_acceleration_units       = repmat({'m/s^2'},1,numel(oldconfig.session_names));
        warning('Config field bids_motion_acceleration_units unspecified - assuming meters per square second')
    end

% angularacceleration
%-----------------------------------------------------------
    if isfield(oldconfig, 'bids_motion_angularacceleration_units')
        if ~iscell(oldconfig.bids_motion_angularacceleration_units)
            newconfig.bids_motion_angularacceleration_units = {newconfig.bids_motion_angularacceleration_units};
        end

        if numel(oldconfig.bids_motion_angularacceleration_units) ~= numel(oldconfig.session_names)
            if numel(oldconfig.bids_motion_angularacceleration_units) == 1
                newconfig.bids_motion_angularacceleration_units = repmat(newconfig.bids_motion_angularacceleration_units, 1, numel(oldconfig.session_names));
                warning('Only one orientation unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_angularacceleration_units must have either one entry or the number of entries (in cell array) have to match number of entries in field session_names')
            end
        end
    else
        newconfig.bids_motion_angularacceleration_units       = repmat({'rad/s^2'},1,numel(oldconfig.session_names));
        warning('Config field bids_motion_angularacceleration_units unspecified - assuming radians per square second')
    end

% mangeticfield
%-----------------------------------------------------------
    if isfield(oldconfig, 'bids_motion_mangeticfield_units')
        if ~iscell(oldconfig.bids_motion_mangeticfield_units)
            newconfig.bids_motion_mangeticfield_units = {newconfig.bids_motion_mangeticfield_units};
        end

        if numel(oldconfig.bids_motion_mangeticfield_units) ~= numel(oldconfig.session_names)
            if numel(oldconfig.bids_motion_mangeticfield_units) == 1
                newconfig.bids_motion_mangeticfield_units = repmat(newconfig.bids_motion_mangeticfield_units, 1, numel(oldconfig.session_names));
                warning('Only one orientation unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_mangeticfield_units must have either one entry or the number of entries (in cell array) have to match number of entries in field session_names')
            end
        end
    else
        newconfig.bids_motion_mangeticfield_units       = repmat({'T'},1,numel(oldconfig.session_names));
        warning('Config field bids_motion_mangeticfield_units unspecified - assuming Tesla')
    end
    
% jointangle
%-----------------------------------------------------------
    if isfield(oldconfig, 'bids_motion_jointangle_units')
        if ~iscell(oldconfig.bids_motion_jointangle_units)
            newconfig.bids_motion_jointangle_units = {newconfig.bids_motion_jointangle_units};
        end

        if numel(oldconfig.bids_motion_jointangle_units) ~= numel(oldconfig.session_names)
            if numel(oldconfig.bids_motion_jointangle_units) == 1
                newconfig.bids_motion_jointangle_units = repmat(newconfig.bids_motion_jointangle_units, 1, numel(oldconfig.session_names));
                warning('Only one orientation unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_jointangle_units must have either one entry or the number of entries (in cell array) have to match number of entries in field session_names')
            end
        end
    else
        newconfig.bids_motion_jointangle_units       = repmat({'rad'},1,numel(oldconfig.session_names));
        warning('Config field bids_motion_jointangle_units unspecified - assuming radians')
    end
    
end

function y = checkequal(x)
% Input 'x' should be cell array
% Output 'y' logical value true. If any input cell array index is equal to
% another else false
% Example1:
% a{1}=[1 1 0]; a{2}=[0 0 0]; a{3}=[0 0 0];
% y = checkequal(a);
% Output is y = logical(1)
% Example2:
% a{1}=[1 1 0]; a{2}=[0 1 0]; a{3}=[0 0 0];
% y = checkequal(a);
% Output is y = logical(0)
y = false;
num = numel(x);
for i = 1:num
    for j = 1:num
        if i~=j
            if isequal(x{i},x{j})
                y = true;
                return;
            end
        end
    end
end
end