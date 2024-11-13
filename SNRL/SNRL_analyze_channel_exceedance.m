function [channel_stats, exceeding_channels] = analyze_channel_exceedance(EEG, amp_threshold, percentage_threshold, skip_labels)

    % this function was written by chatGPT-4, and checked by a human


    % Function to analyze the percentage of samples that exceed a specified amplitude threshold
    % for each channel and return the indices of channels that exceed a given percentage threshold.
    % Channels specified in skip_labels are only skipped in the threshold check, not in the table.
    %
    % Parameters:
    %   EEG                - EEG structure (EEGLAB dataset)
    %   amp_threshold      - Amplitude threshold (absolute value)
    %   percentage_threshold - Percentage of samples that should exceed the threshold to be flagged
    %   skip_labels        - Cell array of channel labels to skip (only for the exceeding channel check)
    %
    % Returns:
    %   channel_stats      - Table with channel labels, indices, percentage of samples exceeding the threshold,
    %                        and the threshold value
    %   exceeding_channels - Indices of channels that exceed the percentage threshold
    
    % Get the number of channels and samples
    num_channels = EEG.nbchan;
    total_samples = size(EEG.data, 2);
    
    % Number of samples required to exceed the threshold
    required_samples = round(percentage_threshold / 100 * total_samples);
    
    % Initialize arrays to store channel labels, indices, exceedance percentages, and threshold values
    channel_labels = cell(num_channels, 1);
    channel_indices = (1:num_channels)';
    exceedance_percentages = zeros(num_channels, 1);
    thresholds = repmat(amp_threshold, num_channels, 1);
    
    % Get the channel indices for the channels that need to be skipped
    skip_indices = find(ismember({EEG.chanlocs.labels}, skip_labels));
    
    % Initialize the array to store the indices of channels that exceed the percentage threshold
    exceeding_channels = [];
    
    % Loop through each channel in the EEG dataset
    for ch = 1:num_channels
        % Get the channel label
        channel_labels{ch} = EEG.chanlocs(ch).labels;
        
        % Get the channel data
        channel_data = EEG.data(ch, :);
        
        % Calculate the percentage of samples that exceed the amplitude threshold
        exceed_count = sum(abs(channel_data) > amp_threshold);
        exceedance_percentages(ch) = (exceed_count / total_samples) * 100;
        
        % Check if the channel is in the skip list before adding to exceeding_channels
        if ~ismember(ch, skip_indices) && exceed_count >= required_samples
            % Add this channel's index to the exceeding channels array
            exceeding_channels = [exceeding_channels, ch];
        end
    end
    
    % Create a table with the channel labels, indices, exceedance percentages, and threshold values
    channel_stats = table(channel_labels, channel_indices, exceedance_percentages, thresholds, ...
                          'VariableNames', {'ChannelLabel', 'ChannelIndex', 'ExceedancePercentage', 'Threshold'});
end
