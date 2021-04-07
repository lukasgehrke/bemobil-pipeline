function bemobil_xdf2bids(bemobil_config, numericalIDs, varargin)

% Examaple script for converting .xdf recordings to BIDS
% see bemobil_bidstools.md 
% 
% Inputs : 
%   bemobil_config
%   example fields 
%       bemobil_config.study_folder             = 'E:\Project_BIDS\example_dataset_MWM\';
%       bemobil_config.filename_prefix          = 'sub_';
%       bemobil_config.raw_data_folder          = '0_raw-data\';
%       bemobil_config.bids_data_folder         = '1_BIDS-data\'; 
%       bemobil_config.filenames                = {'VR' 'desktop'}; 
%       bemobil_config.rigidbody_streams        = {'playerTransform','playerTransfom','rightHand', 'leftHand', 'Torso'};
%       bemobil_config.bids_rbsessions          = [1,1; 1,1; 0,1; 0,1; 0,1]; 
%                                                  logicals : indicate which rbstreams are present in which sessions
%       bemobil_config.bids_eegkeyword          = {'BrainVision'};
%                                                  a unique keyword used to identify the eeg stream in the .xdf file             
%       bemobil_config.bids_tasklabel           = 'VNE1';
%       bemobil_config.channel_locations_filename = 'VN_E1_eloc.elc';
%       bemobil_config.bids_motioncustom        = 'motion_customfunctionname';
%   
%   numericalIDs
%       array of participant numerical IDs in the data set
%  
%--------------------------------------------------------------------------
% Optional Inputs : 
%
%   Note on multi-session and multi-run data sets :  
%
%           Entries in bemobil_config.filenames will search through the 
%           raw data directory of the participant and group together
%           .xdf files with matching keyword in the name into one session
%           If there are multiple files in one session, they will be given
%           separate 'run' numbers in the file name
%           !! IMPORTANT !!
%           The order of runs rely on incremental name sorting 
%           using the "Nature Order File Sorting Tool" - Stephen Cobeldick (2021). Natural-Order Filename Sort (https://www.mathworks.com/matlabcentral/fileexchange/47434-natural-order-filename-sort), MATLAB Central File Exchange. Retrieved March 1, 2021.
%
%           for example,
%                   sub-1\sub-1_VNE1_VR_rec1.xdf
%                   sub-1\sub-1_VNE1_VR_rec2.xdf
%                   sub-1\sub-1_VNE1_desktop.xdf
%           will be organized into
%                   sub-001\ses-VR\sub-001_ses-VR_task-VNE1_run-1_eeg.bdf
%                   sub-001\ses-VR\sub-001_ses-VR_task-VNE1_run-2_eeg.bdf
%                   sub-001\ses-desktop\sub-001_ses-desktop_task-VNE1_eeg.bdf
%
% Author : Sein Jeung (seinjeung@gmail.com)
%--------------------------------------------------------------------------


% input check and default value assignment 
%--------------------------------------------------------------------------

bemobil_config = checkfield(bemobil_config, 'bids_data_folder', '1_BIDS-data\', '1_BIDS-data\'); 
bemobil_config = checkfield(bemobil_config, 'rigidbody_names', bemobil_config.rigidbody_streams, 'values from field "rigidbody_streams"'); 
bemobil_config = checkfield(bemobil_config, 'rigidbody_anat', 'Undefined', 'Undefined'); 

if ~isfield(bemobil_config, 'bids_rbsessions')
    bemobil_config.bids_rbsessions    = true(numel(bemobil_config.filenames),numel(bemobil_config.rigidbody_streams)); 
else
    if ~islogical(bemobil_config.bids_rbsessions)
        bemobil_config.bids_rbsessions = logical(bemobil_config.bids_rbsessions); 
    end
end

bemobil_config = checkfield(bemobil_config, 'bids_eegkeyword','EEG', 'EEG'); 
bemobil_config = checkfield(bemobil_config, 'bids_tasklabel', 'defaulttask', 'defaulttask'); 

if isfield(bemobil_config, 'bids_motion_positionunits')
    if iscell(bemobil_config.bids_motion_positionunits)
        if numel(bemobil_config.bids_motion_positionunits) ~= numel(bemobil_config.filenames)
            if numel(bemobil_config.bids_motion_positionunits) == 1
                bemobil_config.bids_motion_positionunits = repmat(bemobil_config.bids_motion_postionunits, 1, numel(bemobil_config.filenames)); 
                warning('Only one pos unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_positionunits must have either one entry or the number of entries (in cell array) have to match number of entries in field filenames')
            end
        end
    else
        bemobil_config.bids_motion_positionunits = {bemobil_config.bids_motion_positionunits}; 
    end
else
    bemobil_config.bids_motion_positionunits       = repmat({'m'},1,numel(bemobil_config.filenames));
    warning('Config field bids_motion_positionunits unspecified - assuming meters')
end

if isfield(bemobil_config, 'bids_motion_orientationunits')
    if iscell(bemobil_config.bids_motion_orientationunits)
        if numel(bemobil_config.bids_motion_orientationunits) ~= numel(bemobil_config.filenames)
            if numel(bemobil_config.bids_motion_orientationunits) == 1
                bemobil_config.bids_motion_orientationunits = repmat(bemobil_config.bids_motion_orientationunits, 1, numel(bemobil_config.filenames)); 
                warning('Only one orientation unit specified for multiple sessions - applying same unit to all sessions')
            else
                error('Config field bids_motion_orientationunits must have either one entry or the number of entries (in cell array) have to match number of entries in field filenames')
            end
        end
    else
        bemobil_config.bids_motion_orientationunits = {bemobil_config.bids_motion_orientationunits}; 
    end
else
    bemobil_config.bids_motion_orientationunits       = repmat({'rad'},1,numel(bemobil_config.filenames));
    warning('Config field bids_motion_oreintationunits unspecified - assuming radians')
end

%--------------------------------------------------------------------------
% find optional input arguments 
for iVI = 1:2:numel(varargin)
    if strcmp(varargin{iVI}, 'generalmetadata')
        generalInfo         = varargin{iVI+1}; 
    elseif strcmp(varargin{iVI}, 'participantmetadata')
        subjectInfo         = varargin{iVI+1}; 
    elseif strcmp(varargin{iVI}, 'motionmetadata')
        motionInfo          = varargin{iVI+1}; 
    else
        warning('One of the optional inputs are not valid : please see help bemobil_xdf2bids')
    end
end

% check if numerical IDs match subjectData, if this was specified
if exist('subjectInfo','var')
    
    % first sort numerical IDs and rows in subjectdata struct in ascending order
    numericalIDs            = sort(numericalIDs);
    nrColInd                = find(strcmp(subjectInfo.cols, 'nr'));
    subjectInfo.data        = sortrows(subjectInfo.data, nrColInd);
    IDsInSData              = [subjectInfo.data{:,nrColInd}];
    
    if ~isequal(numericalIDs,IDsInSData)
        
        % throw warning if the two ID arrays do not match and take the latter
        warning('Input numericalIDs and entries for column nr in participant metadata do not match - using the latter')
        numericalIDs = IDsInSData;
        
    end
else 
    warning('Optional input participantmetadata was not entered - participant.tsv will be omitted (NOT recommended for data sharing)')
end

%-------------------------------------------------------------------------
% initialize fieldtrip
ft_defaults

% add natsortfiles to path
[filepath,~,~] = fileparts(which('bemobil_xdf2bids')); 
addpath(fullfile(filepath, 'resources', 'natsortfiles'))

% add load_xdf
[filepath,~,~] = fileparts(which('ft_defaults')); 
addpath(fullfile(filepath, 'external', 'xdf'))

% path to sourcedata
sourceDataPath                          = fullfile(bemobil_config.study_folder, bemobil_config.raw_data_folder(1:end-1));
addpath(genpath(sourceDataPath))

% names of the steams 
motionStreamNames                       = bemobil_config.rigidbody_streams;
eegStreamName                           = {bemobil_config.bids_eegkeyword};


if isempty(bemobil_config.bids_motionconvert_custom)
    % funcions that resolve dataset-specific problems
    motionCustom            = 'bemobil_bids_motionconvert';
else 
    motionCustom            = bemobil_config.bids_motionconvert_custom; 
end

% general metadata that apply to all participants
if ~exist('generalInfo', 'var')
    
    warning('Optional input generalmetadata was not entered - using default general metadata (NOT recommended for data sharing)')
    
    generalInfo = [];
    
    % root directory (where you want your bids data to be saved)
    generalInfo.bidsroot                                = fullfile(bemobil_config.study_folder, bemobil_config.bids_data_folder);
    
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
    generalInfo.task                                    = bemobil_config.bids_tasklabel;

end

cfg = generalInfo;

%--------------------------------------------------------------------------
% loop over participants
for pi = 1:numel(numericalIDs)
    
    participantNr   = numericalIDs(pi);
    participantDir  = fullfile(sourceDataPath, [bemobil_config.filename_prefix num2str(participantNr)]);
    
    % find all .xdf files for the given session in the participant directory
    participantFiles    = dir(participantDir);
    fileNameArray       = {participantFiles.name};
    
    % loop over sessions
    for si = 1:numel(bemobil_config.filenames)
        
        sessionFiles        = participantFiles(contains(fileNameArray, '.xdf') & contains(fileNameArray, bemobil_config.filenames{si}));
        
        % sort files by natural order
        sortedFileNames     = natsortfiles({sessionFiles.name});
        
        % loop over files in each session.
        % Here 'di' will index files as runs.
        for di = 1:numel(sortedFileNames)
            
            % construct file and participant- and file- specific config
            % information needed to construct file paths and names
            cfg.sub                                     = num2str(participantNr,'%03.f');
            cfg.dataset                                 = fullfile(participantDir, sortedFileNames{di});
            cfg.ses                                     = bemobil_config.filenames{si};
            cfg.run                                     = di;
            
            % remove session label in uni-session case
            if numel(bemobil_config.filenames) == 1
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
                    
                end
                
            end
            
            xdfeeg      = streams(contains(names,eegStreamName) & iscontinuous);
            xdfmotion   = streams(contains(names,motionStreamNames(bemobil_config.bids_rbsessions(si,:))) & iscontinuous);
      
            %--------------------------------------------------------------
            %                  Convert EEG Data to BIDS
            %--------------------------------------------------------------
            % construct fieldtrip data
            eeg        = stream2ft(xdfeeg{1}); 
    
            % save eeg start time
            eegStartTime                = eeg.time{1}(1); 
            
            % construct eeg metadata
            bemobil_bids_eegcfg;
            
            % read in the event stream (synched to the EEG stream)
            events                = ft_read_event(cfg.dataset);
            
            % event parser script
            if isempty(bemobil_config.bids_parsemarkers_custom)
                [events, eventsJSON] = bemobil_bids_parsemarkers(events);
            else
                [events, eventsJSON] = feval(bemobil_config.bids_parsemarkers_custom, events);
            end
            
            eegcfg.events = events;
            
            if isfield(bemobil_config, 'channel_locations_filename')      
                eegcfg.elec = fullfile(participantDir, [bemobil_config.filename_prefix, num2str(participantNr) '_' bemobil_config.channel_locations_filename]); 
            end
            
            % write eeg files in bids format
            data2bids(eegcfg, eeg);
            
            %--------------------------------------------------------------
            %                Convert Motion Data to BIDS
            %--------------------------------------------------------------
            motionsrates = []; 
            
            % construct fieldtrip data
            for iM = 1:numel(xdfmotion)
                ftmotion{iM} = stream2ft(xdfmotion{iM}); 
            end
            
             % if needed, execute a custom function for any alteration to the data to address dataset specific issues
            % (quat2eul conversion, unwrapping of angles, resampling, wrapping back to [pi, -pi], and concatenating for instance)
            motion = feval(motionCustom, ftmotion, motionStreamNames(bemobil_config.bids_rbsessions(si,:)), pi, si, di);
                     
            % save motion start time
            motionStartTime              = motion.time{1}(1);
            
            % construct motion metadata
            bemobil_bids_motioncfg;

            % write motion files in bids format
            data2bids(motioncfg, motion);
            
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

% events.json
eJSONName       = fullfile(cfg.bidsroot, ['task-' cfg.task '_events.json']);
efid            = fopen(eJSONName, 'wt');
eString         = savejson('', eventsJSON, 'NaN', '"n/a"', 'ParseLogical', true);
fwrite(efid, eString); fclose(efid);

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
hdr.Fs                  = xdfstream.info.effective_srate;
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