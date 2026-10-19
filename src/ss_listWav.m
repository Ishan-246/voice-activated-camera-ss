function files = ss_listWav(folder, pattern)
%SS_LISTWAV  Sorted full paths of WAV files in a folder matching a pattern.
files = {};
if ~exist(folder, 'dir'), return; end
d = dir(fullfile(folder, pattern));
d = d(~[d.isdir]);
names = sort({d.name});
files = cell(1, numel(names));
for k = 1:numel(names)
    files{k} = fullfile(folder, names{k});
end
end
