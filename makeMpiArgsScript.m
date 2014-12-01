mpiexecCommand = '/usr/cac/rhel6/mpiexec/bin/mpiexec';
mpiexecArgs = sprintf('-n %d', props.NumberOfTasks);

% BELOW is the code used to debug mpiexec issues on a single computer
% running the local cluster smpd daemon
% import com.mathworks.toolbox.distcomp.local.SmpdDaemonManager
% % Get all the args from the SmpdGateway
% mpiargs = parallel.internal.apishared.SmpdGateway.getMpiexecArgs(variables(:,1));
% if ~SmpdDaemonManager.getManager.isDaemonInUse
%     SmpdDaemonManager.getManager.getPortAndIncrementUsage;
% end
% % Get the current port number for the daemon
% spmdPort = SmpdDaemonManager.getManager.getPortAndIncrementUsage;
% SmpdDaemonManager.getManager.releaseUsage;
% 
% mpiexecArgs = sprintf('%s %s %s', ...
%     sprintf('%s ', mpiargs{2:end}), ...
%     sprintf('-port %d', spmdPort), ...
%     sprintf('-hosts 1 127.0.0.1 %d', props.NumberOfTasks) );
% 
% mpiexecCommand = mpiargs{1};
