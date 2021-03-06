#!/bin/bash
# Feat's (v.4.1.9) unwarp module.

# Based on FSL's featlib.tcl (v. 4.1.9). 
# Adapted by Andreas Heckel
# University of Heidelberg
# heckelandreas@googlemail.com
# https://github.com/ahheckel
# 12/15/2012

set -e

trap 'echo "$0 : An ERROR has occured."' ERR

#wdir=`pwd`/.unwarp$$
#trap "echo -e \"\ncleanup: erasing '$wdir'\" ; rm -f $wdir/* ; rmdir $wdir ; exit" EXIT
    
Usage() {
    echo ""
    echo "Usage: `basename $0` <input func> <fmap> <fmap-magn brain> <uw-dir x/y/z/x-/y-/z-> <TE(s)> <ESP(ms)> <siglossthres(%)> <outdir>"
    echo ""
    exit 1
}

[ "$8" = "" ] && Usage    
  
funcdata="$1"
fmap="$2"
fmap_mag="$3"
unwarp_dir="$4"
TE=$5 #30
dwell=$6 #0.23
signallossthresh=$7 # recommended: bold: 10 , dwi: 100
out="$8"

wdir=$out ; mkdir -p $wdir
sdir=`pwd`

# FM = space of fieldmap
# EF = space of example_func
# UD = undistorted (in any space)
# D  = distorted (in any space)

echo "`basename $0`: input           : $funcdata"
echo "`basename $0`: fmap            : $fmap"
echo "`basename $0`: magn            : $fmap_mag"
echo "`basename $0`: uwdir           : $unwarp_dir"
echo "`basename $0`: TE(ms)          : $TE"
echo "`basename $0`: ESP(ms)         : $dwell"
echo "`basename $0`: SigLossThres(%) : $signallossthresh"

total_volumes=`fslnvols $funcdata 2> /dev/null`
echo "`basename $0`: Total original volumes = $total_volumes"

mkdir -p $wdir    
  
  echo "`basename $0`: copy in unwarp input files into '$wdir' subdir."
  #fslmaths ../example_func EF_D_example_func
  fslroi $funcdata $wdir/example_func $(echo "$total_volumes / 2" | bc) 1
  fslmaths $wdir/example_func $wdir/EF_D_example_func -odt float
  fslmaths $fmap $wdir/FM_UD_fmap
  fslmaths $fmap_mag $wdir/FM_UD_fmap_mag

cd $wdir

  echo "`basename $0`: generate mask for fmap_mag (accounting for the fact that either mag or phase might have been masked in some pre-processing before being enter to FEAT)"
  fslmaths FM_UD_fmap_mag FM_UD_fmap_mag_brain
  fslmaths FM_UD_fmap_mag -bin FM_UD_fmap_mag_brain_mask -odt short
  
  echo "`basename $0`: remask by the non-zero voxel mask of the fmap_rads image (as prelude may have masked this differently before)"
  echo "  NB: need to use cluster to fill in holes where fmap=0"
  fslmaths FM_UD_fmap -abs -bin -mas FM_UD_fmap_mag_brain_mask -mul -1 -add 1 -bin FM_UD_fmap_mag_brain_mask_inv
  cluster -i FM_UD_fmap_mag_brain_mask_inv -t 0.5 --no_table -o FM_UD_fmap_mag_brain_mask_idx
  maxidx=`fslstats FM_UD_fmap_mag_brain_mask_idx -R | awk '{ print \$2 }'`
  fslmaths FM_UD_fmap_mag_brain_mask_idx -thr $maxidx -bin -mul -1 -add 1 -bin -mas FM_UD_fmap_mag_brain_mask FM_UD_fmap_mag_brain_mask

  echo "`basename $0`: refine mask (remove edge voxels where signal is poor)"
  fslmaths FM_UD_fmap -sub `fslstats FM_UD_fmap -k FM_UD_fmap_mag_brain_mask -P 50` -mas FM_UD_fmap_mag_brain_mask FM_UD_fmap
  thresh50=`fslstats FM_UD_fmap_mag_brain -P 98`
  thresh50=`echo "$thresh50 / 2.0" | bc -l`
  fslmaths FM_UD_fmap_mag_brain -thr $thresh50 -bin FM_UD_fmap_mag_brain_mask50
  fslmaths FM_UD_fmap_mag_brain_mask -ero FM_UD_fmap_mag_brain_mask_ero
  fslmaths FM_UD_fmap_mag_brain_mask_ero -add FM_UD_fmap_mag_brain_mask50 -thr 0.5 -bin FM_UD_fmap_mag_brain_mask
  fslmaths FM_UD_fmap -mas FM_UD_fmap_mag_brain_mask FM_UD_fmap
  
  echo "`basename $0`: run despiking filter just on the edge voxels"
  fslmaths FM_UD_fmap_mag_brain_mask -ero FM_UD_fmap_mag_brain_mask_ero
  fugue --loadfmap=FM_UD_fmap --savefmap=FM_UD_fmap_tmp_fmapfilt -m FM_UD_fmap_mag_brain_mask --despike --despikethreshold=2.1 # rem by HKL
  #fugue --loadfmap=FM_UD_fmap --savefmap=FM_UD_fmap_tmp_fmapfilt --mask=FM_UD_fmap_mag_brain_mask --despike --despikethreshold=2.1 # see fsl-list email from Michael Hallquist on 8 Aug 2012 (median filter also turned off as suggested in the reply)
  fslmaths FM_UD_fmap_tmp_fmapfilt -sub FM_UD_fmap -mas FM_UD_fmap_mag_brain_mask_ero -add FM_UD_fmap FM_UD_fmap # rem by HKL
  #fslmaths FM_UD_fmap -sub FM_UD_fmap_tmp_fmapfilt -mas FM_UD_fmap_mag_brain_mask_ero -add FM_UD_fmap_tmp_fmapfilt FM_UD_fmap # see fsl-list email from Michael Hallquist on 8 Aug 2012
  rm -f FM_UD_fmap_tmp_fmapfilt* FM_UD_fmap_mag_brain_mask_ero* FM_UD_fmap_mag_brain_mask50* FM_UD_fmap_mag_brain_i*
  
  echo "`basename $0`: now demean"
  fslmaths FM_UD_fmap -sub `fslstats FM_UD_fmap -k FM_UD_fmap_mag_brain_mask -P 50` -mas FM_UD_fmap_mag_brain_mask FM_UD_fmap
  
  echo "`basename $0`: get a sigloss estimate and make a siglossed mag for forward warp"
  epi_te=`echo "$TE / 1000.0" | bc -l`
  sigloss -i FM_UD_fmap --te=$epi_te -m FM_UD_fmap_mag_brain_mask -s FM_UD_fmap_sigloss
  siglossthresh=`echo "1.0 - ( $signallossthresh / 100.0 )" | bc -l`
  fslmaths FM_UD_fmap_sigloss -mul FM_UD_fmap_mag_brain FM_UD_fmap_mag_brain_siglossed -odt float
      
  echo "`basename $0`: make a warped version of FM_UD_fmap_mag to match with the EPI"
  dwell=`echo "$dwell / 1000.0" | bc -l`
  fugue -i FM_UD_fmap_mag_brain_siglossed --loadfmap=FM_UD_fmap --mask=FM_UD_fmap_mag_brain_mask --dwell=$dwell -w FM_D_fmap_mag_brain_siglossed --nokspace --unwarpdir=$unwarp_dir
  fugue -i FM_UD_fmap_sigloss             --loadfmap=FM_UD_fmap --mask=FM_UD_fmap_mag_brain_mask --dwell=$dwell -w FM_D_fmap_sigloss             --nokspace --unwarpdir=$unwarp_dir
  fslmaths FM_D_fmap_sigloss -thr $siglossthresh FM_D_fmap_sigloss
  #flirt -in EF_D_example_func -ref FM_D_fmap_mag_brain_siglossed -omat EF_2_FM.mat -o grot -dof 6 -refweight FM_D_fmap_sigloss -cost mutualinfo # 'mutualinfo' added by HKL but seems less reliable in fsl v5.0.1
  flirt -in EF_D_example_func -ref FM_D_fmap_mag_brain_siglossed -omat EF_2_FM.mat -o grot -dof 6 -refweight FM_D_fmap_sigloss -cost corratio
  convert_xfm -omat FM_2_EF.mat -inverse EF_2_FM.mat
  
  echo "`basename $0`: put fmap stuff into space of EF_D_example_func"
  flirt -in FM_UD_fmap                -ref EF_D_example_func -init FM_2_EF.mat -applyxfm -out EF_UD_fmap
  flirt -in FM_UD_fmap_mag_brain      -ref EF_D_example_func -init FM_2_EF.mat -applyxfm -out EF_UD_fmap_mag_brain
  flirt -in FM_UD_fmap_mag_brain_mask -ref EF_D_example_func -init FM_2_EF.mat -applyxfm -out EF_UD_fmap_mag_brain_mask
  flirt -in FM_UD_fmap_sigloss        -ref EF_D_example_func -init FM_2_EF.mat -applyxfm -out EF_UD_fmap_sigloss
  fslmaths EF_UD_fmap_mag_brain_mask -thr 0.5 -bin EF_UD_fmap_mag_brain_mask -odt float
  fslmaths EF_UD_fmap_sigloss -thr $siglossthresh EF_UD_fmap_sigloss -odt float      
  
  echo "`basename $0`: apply warp to EF_D_example_func and save unwarp-shiftmap then convert to unwarp-warpfield"
  fugue --loadfmap=EF_UD_fmap --dwell=$dwell --mask=EF_UD_fmap_mag_brain_mask -i EF_D_example_func -u EF_UD_example_func --unwarpdir=$unwarp_dir --saveshift=EF_UD_shift
  #fugue --loadfmap=EF_UD_fmap --dwell=$dwell --mask=EF_UD_fmap_mag_brain_mask -i EF_D_example_func -u EF_UD_example_func --unwarpdir=y --saveshift=EF_UD_shift+ # added by HKL
  #fugue --loadfmap=EF_UD_fmap --dwell=$dwell --mask=EF_UD_fmap_mag_brain_mask -i EF_D_example_func -u EF_UD_example_func --unwarpdir=y- --saveshift=EF_UD_shift- # added by HKL
  convertwarp -s EF_UD_shift -o EF_UD_warp -r EF_D_example_func --shiftdir=$unwarp_dir  
  convertwarp -s EF_UD_shift -o _warp_+y -r EF_D_example_func --shiftdir=y # added by HKL
  convertwarp -s EF_UD_shift -o _warp_-y -r EF_D_example_func --shiftdir=y- # added by HKL
  
  # apply warping to example_func
  immv example_func example_func_orig_distorted
  applywarp -i example_func_orig_distorted -o example_func -w EF_UD_warp -r example_func_orig_distorted --abs
  applywarp -i example_func_orig_distorted -o example_func_uw+y -w _warp_+y -r example_func_orig_distorted --abs # added by HKL
  applywarp -i example_func_orig_distorted -o example_func_uw-y -w _warp_-y -r example_func_orig_distorted --abs # added by HKL
  
cd $sdir

# cleanup    
imrm $wdir/grot

echo "`basename $0`: done."
