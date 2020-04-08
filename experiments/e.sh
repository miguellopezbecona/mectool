#!/bin/bash

# "prueba" pero solo haciendo sleep una vez

packages=$(find /sys/class/powercap/intel-rapl/ -maxdepth 1 -iname "intel-rapl:*")
index=0

# Gets "before" data for each package/domain
for p in $packages
do
	baseDir=$p
	name[$index]=$(cat $baseDir/name)
	before[$index]=$(cat $baseDir/energy_uj)

	# ! path for no including current directory
	subdomains=$(find $baseDir -maxdepth 1 ! -path $baseDir -iname "intel-rapl:*")

	# Gets data for each subdomain
	for sb in $subdomains
	do
		((index++))
		name[$index]="$(cat $baseDir/name)-$(cat $sb/name)"
		before[$index]=$(cat $sb/energy_uj)
	done
	((index++))
done

sleep 1 # Sleeps
index=0

# Gets "after" data for each package/domain
for p in $packages
do
	baseDir=$p
	after[$index]=$(cat $baseDir/energy_uj)

	# ! path for no including current directory
	subdomains=$(find $baseDir -maxdepth 1 ! -path $baseDir -iname "intel-rapl:*")

	# Gets data for each subdomain
	for sb in $subdomains
	do
		((index++))
		after[$index]=$(cat $sb/energy_uj)
	done
	((index++))
done
((index--))

# Obtains results
for i in $(seq 0 $index)
do
	result=$( echo "scale=4; ( ${after[$i]} - ${before[$i]} ) / 1000000" | bc -l )
	echo "${name[$i]}: $result J"
done

