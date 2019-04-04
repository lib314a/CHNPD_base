#!/bin/tcsh

# The template with skull
set rset  = ./CHNPD_v1.4/Asym/chnpd_asym_06.0-07.0_t1w.nii
# The whole brain mask for skull-striping
set mset  = ./CHNPD_v1.4/Asym/chnpd_asym_06.0-07.0_mask.nii
# The grey matter mask
set gset  = ./CHNPD_v1.4/Asym/chnpd_asym_06.0-07.0_gm.nii

# Step 0: skull off brick ------------------------------------------------------

set opref = BRICK0
set blab  = "SKoff"

# mask dset
set fout = "${opref}_${blab}.nii.gz"
3dcalc                              \
    -a "$rset"                      \
    -b "$mset" \
    -expr 'a*b' \
    -prefix ${fout}                 \
    -fscale -short

# use same brick labels as original nii
3drefit -space MNI -sublabel 0 "$blab" $fout

echo "\n\n++ Done: ${fout}\n\n"

# Step 1: skull on brick -------------------------------------------------------

# The template with skull
set iset  = $rset
# The template without skull
set rset  = $fout
set opref = BRICK1
set blab  = "SKon"

# mask dset
set fout = "${opref}_${blab}.nii.gz"
# Just copy the original nii
3dcalc                              \
    -a "$iset"                      \
    -expr 'a' \
    -prefix ${fout}                 \
    -fscale -short

# use same brick labels as original nii
3drefit -space MNI -sublabel 0 "$blab" $fout

echo "\n\n++ Done: ${fout}\n\n"

# Step 2: skull weighted brick -------------------------------------------------

set nblur = 5             # int to mult edge length, for blur rad
set opref = BRICK2        # prefix for tmp files-- clean at end
set tpref = _tmp_brick2   # prefix for tmp files-- clean at end
set blab  = "SKweight"

# get min edge len of voxels for blur est

set md = 100000                  # just a reaaally big value
set ddd = `3dinfo -ad3 "$rset"`  # all vals to sort through
foreach d ( $ddd )
    set ll = `echo " $d < $md" | bc`
    if ( $ll == 1 ) then
        set md = $d
    endif
end
echo "++ Min dim = $md"

set rblur = `echo "$nblur * $md" | bc`
echo "++ Blur size (in mm): $rblur"

# mask brain...
set fout = ${tpref}_00w.nii.gz
3dcalc                              \
    -a "$rset"                      \
    -expr 'step(a)'                 \
    -prefix ${tpref}_00w.nii.gz

# ... and fill in holes in this particular one
set fin  = $fout
set fout = ${tpref}_01w.nii.gz
3dmask_tool                         \
    -fill_holes                     \
    -inputs $fin                    \
    -prefix $fout

# mask of head *outside* brain
3dcalc                              \
    -a "$iset"                      \
    -b "$rset"                      \
    -expr 'step(a)*not(b)'          \
    -prefix ${tpref}_01h.nii.gz

# blur each
3dBlurInMask \
     -input  "$rset"                \
     -mask   ${tpref}_01w.nii.gz    \
     -prefix ${tpref}_02w.nii.gz    \
     -FWHM   $rblur

3dBlurInMask \
     -input  "$iset"                \
     -mask   ${tpref}_01h.nii.gz    \
     -prefix ${tpref}_02h.nii.gz    \
     -FWHM   $rblur

# combine
set fout = "${opref}_${blab}.nii.gz"
3dcalc                              \
    -a ${tpref}_02w.nii.gz          \
    -b ${tpref}_02h.nii.gz          \
    -expr 'a+0.1*b'                 \
    -prefix ${fout}                 \
    -fscale -short

# use same brick labels as original MNI152_2009_template
3drefit -space MNI -sublabel 0 "$blab" $fout

\rm ${tpref}*

echo "\n\n++ Done: ${fout}\n\n"

# Step 3: whole brain mask -----------------------------------------------------

set opref = BRICK3        
set blab  = "Bmask"
set tpref = _tmp_brick3   # prefix for tmp files-- clean at end

set fout  = "${opref}_${blab}.nii.gz"
3dcalc \
  -a "$mset" \
  -expr 'step(a)' \
  -prefix $fout

# use same brick labels as original MNI152_2009_template
3drefit -space MNI -sublabel 0 "$blab" $fout

echo "\n\n++ Done: ${fout}\n\n"

# Step 4: grey matter mask -----------------------------------------------------

set opref = BRICK4
set blab  = "GCmask"

set fout  = "${opref}_${blab}.nii.gz"
3dcalc \
  -a "$gset" \
  -expr 'step(a-0.4)' \
  -prefix $fout
# NOTE: criterion (0.4 here) to be determined

# use same brick labels as original MNI152_2009_template
3drefit -space MNI -sublabel 0 "$blab" $fout

echo "\n\n++ Done: ${fout}\n\n"

# Step 5: combine bricks -------------------------------------------------------

set ipref = BRICK
set oset  = chnpd_asym_6-7_1.0_SSW.nii.gz

set tpref = _tmp_bricks

# concatenate volumes
set fin = ${tpref}_cat.nii.gz
3dTcat -prefix ${fin} ${ipref}*

# CHECK DSET MAX VALUES

# Here, we are making a short dset. This requires that the range of
# values be [0, 32767]; if not, something would need to be done to
# scale a volume(s) down.  A check like this could also be performed
# in earlier scripts...
set maxind = `3dinfo -nvi ${fin}`

echo "++ Checking max values of each brick:"
set allval = ()
set maxval = 0
foreach ii ( `seq 0 1 $maxind` )
    set mm    = `3dinfo -dmax "${fin}[$ii]"`
    set allval = ( $allval $mm )
    set isbig = `echo "$maxval < $mm" | bc`
    if ( $isbig == 1 ) then
        set maxval = "$mm"
    endif
    printf "   [%d]  %10.5f \n" ${ii}  $mm
end    

set badind = ()
foreach ii ( `seq 0 1 $maxind` )
    set mm    = `3dinfo -dmax "${fin}[$ii]"`
    set istoobig = `echo "$mm > 32767" | bc`
    if ( $istoobig == 1 ) then
        set badind = ( $badind $ii )
    endif
end
if ( $#badind > 0 ) then
    echo "** ERROR! These volumes have too large of values to be shorts:"
    foreach ii ( `seq 1 1 ${#badind}` ) 
        printf "   [%d]  %10.5f \n" ${badind[${ii}]}  ${allval[${ii}]}
    end
    echo "** Those would need to be scaled down below 32768."
    exit 1
else
    echo "++ Good:  no values appear to be too big for shorts."
endif

# MAKE FINAL DSET

# If we've made it this far, make final output as unscaled shorts.
3dcalc                              \
    -a ${fin}                       \
    -expr 'a'                       \
    -prefix ${oset}                 \
    -datum short                    \
    -fscale

# clean up
\rm ${tpref}*

echo "\n\n++ Done, final target volume is: $oset\n\n"

exit 0
