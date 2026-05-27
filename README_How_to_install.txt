IMPORTANT INFORMATION for proper installation of the pseudo-CT package.

Require Hardaware:
-	A computer with Matlab installed on it (where this pseudo_CT_package will be installed)
-	SPM8 version installed on the Matlab computer.
-	A computer with FreeSurfer installed (http://surfer.nmr.mgh.harvard.edu)
-	An internet connexion between both computers

Note: Both computers could be the same one (see instructions below).

Once you have downloaded/received your pseudo_CT_package (as either a *.exe of *.zip file), please follow carefully these easy instructions:

	1.- Download the exe/zip file

	2.- Unzip it in a computer with Matlab installed on it. For linux, run the unzip command. For Windows, double click on the *.exe file will unzip the file automatically.
		(IMPORTANT: For Linux and MAC users: make sure the executables Pseudo_CT_executable_for_linux_64bits (or the Pseudo_CT_executable_for_MAC) and the executable spm8 have indeed the execution permissions for the user running the application!!)
	
	IMPORTANT for Linux and MAC!!! If the MCR is not installed, run MCRInstaller, located in:

  		/Your_folder_name/pseudo_CT_package/MCRInstaller.bin (or something similar)
	
	3.- Start matlab.

	4.- Include the spm8 parent folder into the matlab path:
addpath(genpath('C:\Another_folder\spm8'), '-END');

		5.- IMPORTANT!!!!! DO NOT DO this step for DEPLOYED packages!!
			Rename spm_vol_nifti.m  (in spm8\spm_vol_nifti.m) as spm_vol_nifti_orig.m;
			and Rename spm_preproc_write8.m  (in spm8\toolbox\Seg\spm_preproc_write8.m) as spm_preproc_write8_orig.m
			(This will maintain your original spm files).

	6.- Include the parent folder of the package (which could be something like this: C:\Your_folder_name\pseudo_CT_package). For Non-deployed applications include also its subfolders into the matlab path with the following command (don’t forget to add the  '–BEGIN'  !!!):
			FOR NON-DEPLOYED: addpath(genpath('C:\Your_folder\pseudo_CT_package'), '-BEGIN');
			FOR DEPLOYED: addpath('C:\Your_folder\pseudo_CT_package', '-BEGIN');

	7.- Open in matlab the file called    defaults_pseudo_CT.m, by typing in the matlab prompt the following: 
open  defaults_pseudo_CT

	8.- Edit the following fields on that file:

			- HOSTNAME:  It should be the IP address of the computer where FreeSurfer is installed. It could be (or not) the same one where the matlab is running. If it is the same one, then you should write 127.0.0.1.
			- source_command:  It could be that in order to run FreeSurfer commands, FreeSurfer requires to be sourced. If this is the case, then type the command to source it here! If so, don't forget to add a  ;  and a space at the end, otherwise you may hit some trouble here! If there is no need to source FreeSorufre in the HOSTNAME computer, then leave it blank (only the quotes are required, but no need for the   ; and the space).
			- cluster:  if your HOSTNAME computer is a cluster, then type 'Yes', if not then type 'No'. If you are unsure, type 'No'. This is in case your FreeSoftware is installed in a cluster computer, so that we could enjoy a little bit more of power to do certain things. But is not essential and is not going to change your processing time very much, as only certain things (FreeSurfer commands) are run on the HOSTNAME computer anyway.
			- host_folder:	include the host (HOSTNAME computer) folder where your temporary images would be saved. A subfolder would be automatically created with the user's name. Temporary images would be deleted when process is finished, but the users' folder will be maintained (empty), for future uses. If you don't want to specify any folder, just type: '~/' or './' to use the default home folder in the host computer.
			
			- ONLY for DEPLOYED applications!: modify the   key_number   field and input the one that was sent to you by email!!

	9.- Once those fields are edited to match your settings, save the file and you are ready to run. To launch the software, just type on the matlab prompt the following:

			(for NON-deployed packages):   run_pseudo_CT_package
			(for DEPLOYED packages): run_deployed_pseudo_CT_package

	The program will start showing some GUI staff. Just follow the indications (very easy) and around 30 minutes later you should have your pseudo-CT image ready to go!!
	A Congratulations Window will appear when your images are finished!!

This software comes with no warranty. Please, use it under your own responsibility. Please, do not distribute to third parties. In case of doubt, please, contact the developers (see paper below).

Please, if you use this program (or parts of it), please, quote the following paper:

D. Izquierdo-Garcia, A.E. Hansen, S. Förster, D. Benoit, S. Schachoff, S. Fürst, K.T. Chen, D.B. Chonde, and C. Catana.
An SPM8-based Approach for Attenuation Correction Combining Segmentation and Non-rigid Template Formation: Application to Simultaneous PET/MR Brain Imaging. JNM. 2014. Nov;55(11):1825-30.

By Dr. David Izquierdo-Garcia.
Catana Lab
Athinoula A. Martinos Center.
Harvard Medical School / Mass. General Hospital. Boston. USA.
davidizq@nmr.mgh.harvard.edu
