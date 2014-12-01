function setupUmichClusters
% This function will automatically create 2 profiles for the user. The
%
%     'flux' profile allows submission of independent, communicating 
%     and interactive pool jobs to the flux scheduler. These jobs will wait
%     in the overall FLUX queue until resources are available.
%
%     'current' profile allows for submission of communicating and
%     interactive pool jobs to the currently allocated resources. These
%     resources are named 'mother-superior' (the node on which the initial
%     MATLAB is running, and 'sisters' (the resources available for extra
%     work'). Since we are using MPIEXEC as the remote process launcher,
%     only interactive pools and communicating jobs are available in this
%     environment.

% Do not undertake this initialization on WORKERS - it is ONLY valid on an
% interactive MATLAB
if feature('isdmlworker')
    return
end

% Where should we store the job information - the default is ~/matlabdata
% but can be overriden by an environment variable.
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
    iSetUmichIntegrationScriptsForGeneric(g);
    
    % Get the number of workers for the current cluster from the PBS_NP
    % environment variable. Note that in some cases this variable doesn't
    % exist so we need to convert any NaN's from str2double into Inf so the
    % scheduler can be created correctly.
    numWorkers = str2double(getenv('PBS_NP'));
    numWorkers(isnan(numWorkers)) = Inf;
    g.NumWorkers = numWorkers;
    
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
    % communicating job. This is critical
    t.CommunicatingJobWrapper = '/home2/josluke/umich_mpiexec/fluxCommunicatingScript.sh';
    t.SubmitArguments = '-l walltime=00:10:00 -q flux -A support_flux -m abe';
    t.saveProfile;
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

function iSetUmichIntegrationScriptsForGeneric(g)
g.CommunicatingSubmitFcn = @parallel.integration.UMICH.communicatingSubmitFcn;
g.GetJobStateFcn = @parallel.integration.UMICH.getJobStateFcn;
g.CancelJobFcn = @parallel.integration.UMICH.cancelJobFcn;
g.CancelTaskFcn = @parallel.integration.UMICH.cancelTaskFcn;
g.DeleteJobFcn = @parallel.integration.UMICH.deleteJobFcn;
g.DeleteTaskFcn = @parallel.integration.UMICH.deleteTaskFcn;
end