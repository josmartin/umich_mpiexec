classdef ( Sealed ) UMICH
    
    methods ( Static )
        function OK = cancelJobFcn( cluster, job )
            OK = iCancelJobImpl( cluster, job );
        end
        
        function deleteJobFcn( cluster, job )            
            if iShouldCancelBeforeDeletion( job )
                iCancelJobImpl( cluster, job );
            end
        end

        function OK = cancelTaskFcn( cluster, task )
            OK = parallel.integration.UMICH.cancelJobFcn( cluster, task.Parent );
        end
        
        function deleteTaskFcn( cluster, task )
            parallel.integration.UMICH.deleteJobFcn( cluster, task.Parent );
        end
        
        function communicatingSubmitFcn(cluster, job, props)
            iCommunicatingSubmitFcn(cluster, job, props)
        end
        
        function jobState = getJobStateFcn( cluster, job, ~ )
            jobState = iGetJobState( cluster, job );
        end
    end
end

function OK = iCancelJobImpl( cluster, job )
OK = false;
import parallel.integration.MpiexecUtils

schedulerData = cluster.getJobClusterData(job);
[wasSubmitted, isMpi, isAlive, pid, whyNotAlive] = ...
    MpiexecUtils.interpretJobSchedulerData( ...
    cluster.Host, schedulerData, job.Id );

if ~wasSubmitted
    OK = true;
    return
end
if ~isMpi
    % Not an MPIEXEC job - we really shouldn't cancel this
    warning(message('parallelexamples:GenericMPIEXEC:MpiexecCannotCancel', job.Id));
    return
end

if isAlive
    % yes, we can cancel
    try
        dct_psfcns( 'kill', pid );
    catch err
        % Failed to kill - maybe permissions?
        warning(message('parallelexamples:GenericMPIEXEC:MpiexecFailedToKillProcess', job.Id, pid, err.message));
        % return false
        return
    end
    if dct_psfcns( 'isalive', pid )
        % then the "kill" will have warned - return OK == false
        return
    else
        % Set the PID to -1 so that it never gets checked again
        schedulerData.pid = -1;
        cluster.setJobClusterData(job, schedulerData);
        OK = true;
        return
    end
else
    % Why wasn't the job alive?
    if strcmp( whyNotAlive.reason, 'wrongclient' )
        % Not OK - warn and return false
        warning(message('parallelexamples:GenericMPIEXEC:MpiexecUnableToCancel', whyNotAlive.description));
        return
    else
        % The pid simply isn't alive any more, nothing for us to do
        OK = true;
        return
    end
end
end

function tf = iShouldCancelBeforeDeletion( job )
import parallel.integration.MpiexecUtils
import parallel.internal.types.States

switch job.StateEnum
    case { States.Pending, States.Unavailable, States.Destroyed, States.Failed }
        tf = false;
    case { States.Queued, States.Running }
        tf = true;
    case States.Finished
        tf = MpiexecUtils.shouldCancelFinishedJob( job.FinishTime );
end
end


function iCommunicatingSubmitFcn(cluster, job, props)
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericMPIEXEC:SubmitFcnError', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

decodeFunction = 'parallel.cluster.generic.communicatingDecodeFcn';

if ~cluster.HasSharedFilesystem
    error('parallelexamples:GenericMPIEXEC:SubmitFcnError', ...
        'The submit function %s is for use with shared filesystems.', currFilename)
end

if ~strcmpi(cluster.OperatingSystem, 'unix')
    error('parallelexamples:GenericMPIEXEC:SubmitFcnError', ...
        'The submit function %s only supports clusters with unix OS.', currFilename)
end

% The job specific environment variables
% Remove leading and trailing whitespace from the MATLAB arguments
matlabArguments = strtrim(props.MatlabArguments);
variables = {'MDCE_DECODE_FUNCTION', decodeFunction; ...
    'MDCE_STORAGE_CONSTRUCTOR', props.StorageConstructor; ...
    'MDCE_JOB_LOCATION', props.JobLocation; ...
    'MDCE_MATLAB_EXE', props.MatlabExecutable; ... 
    'MDCE_MATLAB_ARGS', matlabArguments; ...
    'MDCE_DEBUG', 'true'; ...
    'MLM_WEB_LICENSE', props.UseMathworksHostedLicensing; ...
    'MLM_WEB_USER_CRED', props.UserToken; ...
    'MLM_WEB_ID', props.LicenseWebID; ...
    'MDCE_LICENSE_NUMBER', props.LicenseNumber; ...
    'MDCE_STORAGE_LOCATION', props.StorageLocation; ...
    'MDCE_CMR', cluster.ClusterMatlabRoot; ...
    'MDCE_TOTAL_TASKS', num2str(props.NumberOfTasks)};
% Trim the environment variables of empty values.
nonEmptyValues = cellfun(@(x) ~isempty(strtrim(x)), variables(:,2));
variables = variables(nonEmptyValues, :);
% Set the remaining non-empty environment variables
for ii = 1:size(variables, 1)
    setenv(variables{ii,1}, variables{ii,2});
end
% Which variables do we need to forward for the job?  Take all
% those that we have set.
variablesToForward = variables(:,1);


% Choose a file for the output. Please note that currently, JobStorageLocation refers
% to a directory on disk, but this may change in the future.
logFile = cluster.getLogLocation(job);

import parallel.internal.apishared.WorkerCommand
import parallel.internal.apishared.FilenameUtils

matlabExe = FilenameUtils.quoteForClient( props.MatlabExecutable );

% ---------------------------------------
%     Specific to LOCAL
% ---------------------------------------

mpiargs = parallel.internal.apishared.SmpdGateway.getMpiexecArgs(variablesToForward);
spmdPort = com.mathworks.toolbox.distcomp.local.SmpdDaemonManager.getManager.getPortAndIncrementUsage;
com.mathworks.toolbox.distcomp.local.SmpdDaemonManager.getManager.releaseUsage;
mpiexecCommand = sprintf('%s %s %s', ...
    sprintf('%s ', mpiargs{:}), ...
    sprintf('-port %d', spmdPort), ...
    sprintf('-hosts 1 127.0.0.1 %d', props.NumberOfTasks) );

mpiexecFilename = mpiargs{1};

% ---------------------------------------
%     END Specific to LOCAL
% ---------------------------------------


submitString = sprintf( '%s %s %s', mpiexecCommand, matlabExe, matlabArguments );
                                 
import parallel.integration.MpiexecUtils
schedulerData = MpiexecUtils.submit( submitString, logFile, '', ...
                                            cluster.Host, cluster.OperatingSystem, ...
                                            mpiexecFilename );

cluster.setJobClusterData(job, schedulerData);
end

function jobState = iGetJobState( obj, job )
import parallel.integration.MpiexecUtils
import parallel.internal.types.States

% If we get here, we know that the job is queued/running, and was
% submitted by Mpiexec.
schedulerData = obj.getJobClusterData(job);
[~, ~, isAlive] = MpiexecUtils.interpretJobSchedulerData( ...
    obj.Host, schedulerData, job.Id );

if isAlive
    % Ok
    jobState = lower(char(States.Running));
else
    jobState = lower(char(States.Unknown));
end
% CJSCluster takes care of hSetTerminalStateFromCluster if necessary.
end
