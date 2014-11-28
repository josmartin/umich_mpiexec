function setupUmichClusters

% Deal with where all jobs from FLUX and CURRENT get stored
if isempty(getenv('SOME_OVERRIDE_FOR_JOB_STORAGE_LOCATION'))
    JSL = fullfile(getenv('HOME'), 'matlabdata');
else
    % TODO - add override for JSL here
end
% Make sure that in all cases the JobStorageLocation actually exists
if ~exist(JSL, 'dir')
    mkdir(JSL)
end

%--------------------------------------------------------------------------
% Configure CURRENT
%
% Configure the 'current' cluster correctly to submit using MPIEXEC from
% the mother-superior to the sister nodes. This requires the custom
% integration found in parallel.integration.UMICH
%--------------------------------------------------------------------------
try
    g = iGetOrCreateCluster('current', 'parallel.cluster.Generic');
    
    g.JobStorageLocation = JSL;
    % The helper below simply sets all the appropriate function handles to
    % enable the MPIEXEC stuff to work
    iSetUmichIntegrationScripts(g);
    g.NumWorkers = str2double(getenv('PBS_NP'));
    g.saveProfile
catch
    warning('Unable to configure the ''current'' profile');
end

%--------------------------------------------------------------------------
% Configure FLUX
%
% Configure the 'current' cluster correctly to submit using MPIEXEC from
% the mother-superior to the sister nodes. This requires the custom
% integration found in parallel.integration.UMICH
%--------------------------------------------------------------------------
try 
    t = iGetOrCreateCluster('flux', 'parallel.cluster.Torque');
    t.JobStorageLocation = JSL;
    % Define the script that is used on the mother-superior to launch a
    % communicating job.
    t.CommunicatingJobWrapper = '/home2/josluke/umich_mpiexec/fluxCommunicatingScript.sh';
    t.SubmitArguments = '-l walltime=00:10:00 -q flux -A support_flux -m abe';
catch
    warning('Unable to configure the ''flux'' profile');
end

end
%--------------------------------------------------------------------------
% Internal helper functions below here
%--------------------------------------------------------------------------

function cluster = iGetOrCreateCluster(profileName, expectedClass)

persistent settings;
if isempty(settings)
    settings = parallel.Settings;
end
% Find the desired profile in our set of profiles
if any(strcmp({settings.Profiles.Name}, profileName))
    cluster = parcluster(profileName);
    % Check that what we have been returned is correct
    if ~isa(cluster, expectedClass)
        % TODO - if user has explicitly defined their own version of this
        % profile name, how should we respond?
        error('Cluster returned by this type is incorrect');
    end
else
    cluster = feval(str2func(expectedClass));
    saveAsProfile(cluster, profileName);
end
end

function iSetUmichIntegrationScripts(g)
g.CommunicatingSubmitFcn = @parallel.integration.UMICH.communicatingSubmitFcn;
g.GetJobStateFcn = @parallel.integration.UMICH.getJobStateFcn;
g.CancelJobFcn = @parallel.integration.UMICH.cancelJobFcn;
g.CancelTaskFcn = @parallel.integration.UMICH.cancelTaskFcn;
g.DeleteJobFcn = @parallel.integration.UMICH.deleteJobFcn;
g.DeleteTaskFcn = @parallel.integration.UMICH.deleteTaskFcn;
end