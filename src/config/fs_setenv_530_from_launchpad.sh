#############################################################################
# Name:    nmr-stable53-env
# Purpose: sets up the environment to run the MGH-NMR standard MRI processing
#          stream: unpacking, functional, structural, and visualization.
# Usage:   source /usr/local/freesurfer/nmr-stable53-env
#
# $Id: Exp $
#
#############################################################################

# Point to stable v5.3.0 freesurfer
setenv FREESURFER_HOME /usr/local/freesurfer/stable5_3_0
unsetenv NO_FSFAST
setenv FSFAST_HOME     $FREESURFER_HOME/fsfast
unsetenv NO_MINC

# Source the FreeSurfer Environment File
set FS_ENV_FILE =  $FREESURFER_HOME/SetUpFreeSurfer.csh
if(! -e $FS_ENV_FILE) then
  echo "ERROR: cannot find $FS_ENV_FILE"
  exit 1;
endif
setenv SET_TCL_VARS 1
source $FS_ENV_FILE

# TCLLIBPATH is defined in FreeSurferEnv.csh to ensure compatibility
# in the public distributions, but creates a tix library
# conflict with FSL, so unset it.
unsetenv TCLLIBPATH

### Create a prompt to indicate the standard environment ###
set this_shell    = `basename $SHELL`;
set this_hostname = `hostname` 
set this_host     = `basename $this_hostname .nmr.mgh.harvard.edu`
if(! $?FSENV_KEEP_PROMPT ) then
  if($this_shell == csh) then
    unalias cd
    alias cd  'set old=$cwd; chdir \!*; 
    set tmpcwd = `basename $cwd`; 
    set prompt = "$this_host"":$tmpcwd (nmr-stable53-env) % "'
    cd $cwd;
  else
    set prompt = "[%m:%c] (nmr-stable53-env) "
  endif
endif

### Dont leave huge cores around ###
limit coredumpsize 0

# Add pubsw to the path if it isn't there.
if ( "${path}" !~ */usr/pubsw/bin* ) then
  set path = ( /usr/pubsw/bin $path )
endif

if(! $?MRI_UMASK) then
  setenv MRI_UMASK 2
endif

setenv RECONALL_USAGE_FILE /space/freesurfer/recon-all_run_log

rehash;

unset echo ;
unset verbose;

exit 0;
####################################################################