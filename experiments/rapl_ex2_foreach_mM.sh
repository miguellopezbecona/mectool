#!/bin/bash

## Execute this after experiment_all_combinations.sh. Parameter: base folder where t[th]_m[m]_M[M] folders are

basedir=~/files

# Folder must exist
if [ "$#" -eq 1 -a -e $1 ]; then
	basedir=$1
fi

nodes=$(ls -d $basedir/t*_m*_M* | cut -d '_' -f 2  | cut -c2 | uniq)
numth=$(ls -d $basedir/t*_m*_M* | cut -d '_' -f 1 | rev | cut -d 't' -f 1 | rev | uniq)
if [ -z $numth ]; then
	exit 1
fi

for l in $nodes; do
	for r in $nodes; do
		if [ $l -eq $r ]; then
			continue
		fi

		base=m${l}_M${r}
		dataf=t${numth}_$base
		imgf=img_$base
		imgp=$basedir/$imgf
		
		mkdir $imgp
		Rscript rapl_ex2.R $basedir/$dataf
		mv *.png $imgp

		# Divides images into different folders depending on "o" values
		mkdir $imgp/o_0
		mkdir $imgp/o_med
		mkdir $imgp/o_max
		mv $imgp/*_o0*.png $imgp/o_0
		mv $imgp/*_o5*.png $imgp/o_med
		mv $imgp/*_o1*.png $imgp/o_max
	done
done



