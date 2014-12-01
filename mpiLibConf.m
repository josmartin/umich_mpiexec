function [lib, extras] = mpiLibConf

% Default back to installed MPICH2 if using local scheduler
if ~isempty(getenv('MDCE_USE_ML_LICENSING'))
    [lib, extras] = distcomp.mpiLibConfs( 'default' );
    return
end

mpich = '/home/software/rhel6/mpich/1.4.1p1/lib/';

lib = fullfile(mpich, 'libmpich.so');
mpl = fullfile(mpich, 'libmpl.so');
opa = fullfile(mpich, 'libopa.so');

extras = {mpl, opa};
