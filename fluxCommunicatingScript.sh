#!/bin/sh
#PBS -j oe
# 
# This script uses the following environment variables set by the submit MATLAB code:
# MDCE_CMR            - the value of ClusterMatlabRoot (may be empty)
# MDCE_MATLAB_EXE     - the MATLAB executable to use
# MDCE_MATLAB_ARGS    - the MATLAB args to use
#
# The following environment variables are forwarded through mpiexec:
# MDCE_DECODE_FUNCTION     - the decode function to use
# MDCE_STORAGE_LOCATION    - used by decode function 
# MDCE_STORAGE_CONSTRUCTOR - used by decode function 
# MDCE_JOB_LOCATION        - used by decode function 
# MDCE_DEBUG               - used to debug problems on the cluster

# Copyright 2006-2012 The MathWorks, Inc.

# Create full paths to mw_smpd/mw_mpiexec if needed
FULL_MPIEXEC=!/usr/cac/rhel6/mpiexec/bin/mpiexec
MPIEXEC_CODE=0


# Now that we have launched the SMPDs, we must install a trap to ensure that
# they are closed either in the case of normal exit, or job cancellation:
# Default value of the return code
cleanupAndExit() {
    echo ""
    echo "Exiting with code: ${MPIEXEC_CODE}"
    exit ${MPIEXEC_CODE}
}

runMpiexec() {
    
    if [ ${MDCE_USE_ATTACH} = "on" ] ; then
        attach="pbs_attach -j ${PBS_JOBID}"
    else
        attach=""
    fi

    GENVLIST="MDCE_DECODE_FUNCTION,MDCE_STORAGE_LOCATION,MDCE_STORAGE_CONSTRUCTOR,MDCE_JOB_LOCATION,MDCE_DEBUG,MDCE_SCHED_TYPE,MLM_WEB_LICENSE,MLM_WEB_USER_CRED,MLM_WEB_ID"

    # As a debug stage: echo the command line...
    echo \"${FULL_MPIEXEC}\"  \"${MDCE_MATLAB_EXE}\" ${MDCE_MATLAB_ARGS}
    
    # ...and then execute it
    eval \"${FULL_MPIEXEC}\"  \"${MDCE_MATLAB_EXE}\" ${MDCE_MATLAB_ARGS} < /dev/null
    MPIEXEC_CODE=${?}
}

# Define the order in which we execute the stages defined above
MAIN() {
    trap "cleanupAndExit" 0 1 2 15
    runMpiexec
    exit ${MPIEXEC_CODE}
}

# Call the MAIN loop
MAIN