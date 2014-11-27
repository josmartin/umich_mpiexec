%MpiexecUtils Utility methods support mpiexec clusters

% Copyright 2011-2013 The MathWorks, Inc.

classdef ( Hidden, Sealed ) MpiexecUtils

    properties ( Constant )
        % See the javadoc for java.util.Date - this is precisely the format that we expect
        % from the "toString" method of a java.util.Date - something like
        % "Tue Mar 28 11:41:15 BST 2006". Note that
        % date = java.util.Date;
        % java.util.Date( date.toString )
        % doesn't work!
        DateFormat = java.text.SimpleDateFormat( 'E MMM dd H:m:s z yyyy', java.util.Locale.US );
    end


    methods ( Static )

        function data = submit( submitString, stdout_fname, batName, clusterHost, clusterOs, mpiexecFilename )

        % First, write the submitString to the log file.
            fh = fopen( stdout_fname, 'wt' );
            if fh==-1
                error(message('parallel:cluster:MpiexecCannotWriteLogFile', stdout_fname));
            end
            fprintf( fh, '%s\n', submitString );
            fclose( fh );

            % Handle the environment
            storedEnv = distcomp.pClearEnvironmentBeforeSubmission();
            cleanup = onCleanup( @() distcomp.pRestoreEnvironmentAfterSubmission( storedEnv ) );
            if ispc
                % Create a temporary BAT file
                fh = fopen( batName, 'wt' );
                if fh == -1
                    error(message('parallel:cluster:MpiexecFailedToWriteBatchFile', batName));
                end
                fprintf( fh, '@echo Running mpiexec...\n' );
                fprintf( fh, '@%s >> "%s" 2>&1\n', submitString, stdout_fname );
                fprintf( fh, '@exit\n' );
                fclose( fh );

                pid = dct_psfcns( 'winlaunchproc', batName, '' );
                % Wait to allow the batch script to launch mpiexec
                pid = iGetChildPidWithTimeout( mpiexecFilename, pid, 5 );

                % Nothing to ignore in the pid name
                pidNameIgnorePattern = '';
            else
                % Set the environment variable MDCE_INPUT_REDIRECT. This is used by the
                % exec_redirect.sh script on UNIX clients. We must always redirect stdin on
                % mac, otherwise the mpiexec process does not work correctly. Otherwise, we
                % only redirect stdin if the machine type is PC to prevent repeated
                % prompting for credentials. Note that piping stdin to mpiexec causes it to
                % max out CPU usage on UNIX platforms other than MAC, so we avoid this
                % wherever possible.
                import parallel.internal.apishared.OsType
                clusterOsType = OsType.fromName( clusterOs );
                if clusterOsType == OsType.PC
                    setenv( 'MDCE_INPUT_REDIRECT', 'yes' );
                elseif ismac
                    setenv( 'MDCE_INPUT_REDIRECT', 'null' );
                else
                    setenv( 'MDCE_INPUT_REDIRECT', 'no' );
                end

                % Call helper shell script which deals with stdout and stderr redirection
                scriptTrail = fullfile( 'bin', 'util', 'exec_redirect.sh' );
                script = fullfile( toolboxdir('distcomp'), scriptTrail );

                % Pre-allocate pid to be an invalid PID
                pid = 0;

                [s, w] = dctSystem( sprintf( '%s "%s" %s', script, stdout_fname, submitString ) );
                if s == 0
                    pid = str2double( w );
                    if isnan( pid )
                        warning(message('parallel:cluster:MpiexecFailedToExtractPid', w));
                    end
                else
                    warning(message('parallel:cluster:MpiexecLaunchFailed', s, strtrim( w )));
                end

                % Unset MDCE_INPUT_REDIRECT now we're done with it
                setenv('MDCE_INPUT_REDIRECT', ''  );

                % Ignore the exec redirect pattern in the PID name.
                pidNameIgnorePattern = scriptTrail;
            end

            % Try to extract the process name
            try
                % If we get through to checking the name of the child PID too soon, it's
                % just about possible to see the name of the exec_redirect script if
                % there's a delay between the fork and exec pieces of the background
                % mpiexec launching. Therefore, make sure that the pid name we extract
                % doesn't match exec_redirect.
                pidname = iGetPidNameWithTimeout( pid, pidNameIgnorePattern, 5 );
            catch E %#ok<NASGU> ignore this exception - we're going to warn.
                    % We only get here if there was a problem extracting the name from a living
                    % process
                pidname = '<Unknown>';
                warning(message('parallel:cluster:MpiexecNoProcessName', pid));
            end
            % Create scheduler data so that we can retrieve stdout.
            data = struct( 'type', 'mpiexec', ...
                           'pid', pid, ...
                           'pidname', pidname, ...
                           'pidhost', clusterHost );
        end

        function shouldCancel = shouldCancelFinishedJob( jobFinishTime )
            import parallel.integration.MpiexecUtils

            % This is the amount by which a job must have been finished by in order not
            % to attempt to kill the PID if we can. This timeout can be really long
            % because if destroy is called on the submission client, then
            % cancellation of an already-gone mpiexec process doesn't cause any
            % warnings etc.
            FINISHED_TIMEOUT_MILLIS = 600000;

            if isempty( jobFinishTime )
                % How did we get here? Job must be finished, but we don't have a finish
                % time. Don't warn though as it is not a useful warning
                % don't try to cancel
                shouldCancel = false;
            else
                % Check finish time to see if we should
                nowDateObj = java.util.Date;
                try
                    jobfinishedDateObj = MpiexecUtils.DateFormat.parse( jobFinishTime );
                catch E %#ok<NASGU> Don't need information from the parse error
                        % parse error - warn and break out early
                    warning(message('parallel:cluster:MpiexecDateFormat', jobFinishTime));
                    shouldCancel = false;
                    return
                end
                finishedByMillis = nowDateObj.getTime - jobfinishedDateObj.getTime;

                % Cancel if job finished within FINISHED_TIMEOUT of now.
                shouldCancel = finishedByMillis < FINISHED_TIMEOUT_MILLIS;
            end
        end

        function [wasSubmitted, isMpi, isAlive, pid, whyNotAlive] = interpretJobSchedulerData( clientHost, data, jobId )
        % pInterpretJobSchedulerData - interpret the job scheduler data and return status flags
        %
        % - wasSubmitted is true iff it looks like the job was submitted
        % - isMpi is true iff wasSubmitted is true AND the job has valid
        %   MPIEXEC scheduler data (returns "false" for old jobs)
        % - isAlive is true iff isMpi is true AND the PID is alive AND the PID has
        %   the correct name AND we're on the right client
        % - pid is the pid if the job if isAlive is true, else -1
        % - whyNotAlive.reason is one of {'wrongclient', 'wrongpidname', 'pidnotalive', 'wrongjobtype', 'notsubmitted'}
        % - whyNotAlive.description is a textual description of why the process is not considered to be alive
        % defaults
            wasSubmitted = false;
            isMpi        = false;
            isAlive      = false;
            pid          = -1;
            whyNotAlive  = struct( 'reason', 'notsubmitted', ...
                                   'description', ...
                                   sprintf( 'job %d has not yet been submitted', jobId ) );

            if isempty( data )
                % use defaults
                return
            else
                wasSubmitted = true;
            end

            if strcmp( data.type, 'mpiexec' ) && isfield( data, 'pid' )
                isMpi = true;
            else
                whyNotAlive  = struct( 'reason', 'wrongjobtype', ...
                                       'description', ...
                                       sprintf( 'job %d is not a valid MPIEXEC job', jobId ) );
                return
            end

            % Check the pid for validity before returning it to anyone
            if strcmp( data.pidhost, clientHost )
                % We can start checking things to do with the PID
                if data.pid > 0
                    [pidname, isAlive] = dct_psname( data.pid );
                    if isAlive
                        if strcmp( data.pidname, pidname )
                            % Process is alive, and name matches
                            pid = data.pid;
                            whyNotAlive = struct( 'reason', '', ...
                                                  'description', '' );
                        else
                            % Wrong process name
                            isAlive     = false;
                            whyNotAlive = struct( 'reason', 'wrongpidname', ...
                                                  'description', ...
                                                  sprintf( 'the PID (%d) associated with job %d did not have the expected name', ...
                                                           data.pid, jobId ) );
                        end
                    else
                        whyNotAlive = struct( 'reason', 'pidnotalive', ...
                                              'description', ...
                                              sprintf( 'the PID (%d) associated with job %d is no longer alive', ...
                                                       data.pid, jobId ) );
                    end
                else
                    % invalid pid
                    whyNotAlive = struct( 'reason', 'pidnotalive', ...
                                          'description', ...
                                          sprintf( 'job %d no longer has a valid PID', jobId ) );
                end
            else
                whyNotAlive = struct( 'reason', 'wrongclient', ...
                                      'description', ...
                                      sprintf( 'job %d was submitted from client %s', jobId, data.pidhost ) );
            end
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% iGetPidNameWithTimeout - Get the name of a given PID, but ignore the name
% if it contains our wrapper script - at least until the timeout expires
function name = iGetPidNameWithTimeout( pid, pattern, timeout )

    timeWaited = 0;
    pause_amt  = 0.25;
    name       = dct_psname( pid );

    % Get here if there's no pattern to ignore (i.e. Windows)
    if isempty( pattern )
        return;
    end

    while ~isempty( strfind( name, pattern ) ) && ...
            timeWaited < timeout

        name = dct_psname( pid );

        if isempty( strfind( name, pattern ) )
            break;
        else
            pause( pause_amt );
            timeWaited = timeWaited + pause_amt;
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% iGetChildPidWithTimeout - wait for the given PID to launch a child
% process. If after the timeout, the parent is alive but we haven't found a
% child, then warn. If the parent dies and we never find the child, just
% return the parent process.
function child = iGetChildPidWithTimeout( processFilename, parent, timeout )

    timeWaited = 0;
    child = [];

    % On Windows 8, there are 2 processes associated with a .bat file, so we 
    % need to check the name of the processes before getting the mpiexec pid.
    % On Windows 7 and earlier, there is only 1 child process.
    pause_amt = 0.25;
    while dct_psfcns( 'isalive', parent ) && ...
            isempty( child )  && ...
            timeWaited < timeout
        pause( pause_amt );
        timeWaited = timeWaited + pause_amt;
        childProcs = dct_psfcns( 'winchildren', parent );
        if length( childProcs ) > 1
            child = iFindWindowsPIDByName(processFilename, childProcs );
        elseif length( childProcs ) == 1
            child = childProcs;
        end
    end

    if isempty( child )
        child = parent;
        if dct_psfcns( 'isalive', parent )
            warning(message('parallel:cluster:MpiexecFailedToLaunch'));
        end
    else
        if length( child ) ~= 1
            error(message('parallel:cluster:MpiexecMultipleChildProcesses'));
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Grovel through the supplied PID and see if any of them correspond to the 
% mpiexec process.
function mpiexecPID = iFindWindowsPIDByName( desiredProcName, pids )
    % Strip off any path information from the process name.
    [~, desiredProcName, desiredProcExt] = fileparts(desiredProcName);

    mpiexecPID = [];
    for ii = 1:length( pids )
        procName = dct_psfcns( 'winprocname', pids(ii) );
        [~, pName, pExt] = fileparts(procName);

        % Compare the process name and the extension if one was supplied.
        if strcmpi( desiredProcName, pName ) && ...
            ( isempty( desiredProcExt ) || strcmpi( desiredProcExt, pExt ) )
            mpiexecPID = pids(ii);
            break;
        end
    end
end