function [lib, extras] = mpiLibConf
%MATLAB MPI Library overloading for Infiniband and Ethernet Networks
%
%USAGE
%   place in ~/matlab/mpiLibConf.m
%   edit and set 'network' to ib or ethernet
%   If unsure of the correct value contact hpc-support@umich.edu
%
%   Users who do not edit or set MATLAB_NETWORK will get ib if on flux* queues
%   Users who do not edit or set MATLAB_NETWORK will get ethernet on all others
%
%   Users who wish to control per job (mixing network type) can set
%   MATLAB_NETWORK in their environment
%
%DETAILS
%   Users should use ib (mvapich2) for Infiniband networks such as the Flux Cluster
%   Infiniband is a high performance low latancy network which should give parallel
%   applications much better performance accross multiple nodes
%
%   If a user is using ethernet networks they should use ehternet (mpich2)
%   Ethernet is much lower performing but exists on all systems.
%
%MATLAB_NETWORK
%   Envrionment variable that trumps all other settings and can be used on a per run basis
%
%   Ver 2.0
%   Brock Palen
%   hpc-support@umich.edu

% network can be 'ib' or 'ethernet'
network = '';

%MATLAB_NETWORK can be set in the environment to control what network type
mnetwork = getenv('MATLAB_NETWORK');
if mnetwork
    %disp('$MATLAB_NETWORK overrides setting in mpiLibConf.m')
    network=mnetwork;
end

%check if 'network' is undefined, if so check $PBS_QUEUE if flux set to ib else ethernet and print that
if isempty(network)
    disp('network undefined checking PBS queue')
    if regexpi(getenv('PBS_QUEUE'), 'flux')
        disp('found flux queue assuming infiniband')
        network='ib';
    else
        disp('not in flux queue assume ethernet')
        disp('see help mpiLibConf for forcing infiniband networks')
        network='ethernet';
    end
end

if  strcmpi(network, 'ib')
    %for IB (verbs/Flux) networks
    if regexpi(getenv('PBS_QUEUE'), 'flux')
        mpich = '/usr/flux/software/rhel6/intel/13.1/impi/4.1.1.036/intel64/lib/';
    else
        mpich = '/usr/caen/intel-13.0.1/impi/4.1.0.024/intel64/lib/';
    end
    disp('Using Infiniband')
elseif strcmpi(network, 'ethernet');
    % for ethernet (Most Nyx) networks
    mpich = '/home/software/rhel6/mpich/1.4.1p1/lib/';
    disp('Using Ethernet')
else
    % no values entred
    disp('network is not set')
    disp('valid values are ib or ethernet')
    error('run:  help mpiLibConf.m for help or email hpc-support@umich.edu')
end

lib = strcat(mpich, 'libmpich.so');

mpl = strcat(mpich, 'libmpl.so');
opa = strcat(mpich, 'libopa.so');

extras = {};
%extras = {mpl, opa};

%lib = '/home/software/rhel6/mvapich2/1.8/lib/libmpich.so';
%extras = {'/home/software/rhel6/mvapich2/1.8/lib/libmpl.so',
%          '/home/software/rhel6/mvapich2/1.8/lib/libopa.so'};