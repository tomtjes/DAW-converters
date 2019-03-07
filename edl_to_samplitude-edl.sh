#!/bin/bash
#
# edl_to_samplitude-edl.sh
# converts an EDL (Edit Decision List) file to a Samplitude EDL file
#
# Tools exporting EDL include Trint
# Tools able to import Samplitude EDL include Reaper, Samplitude
#
# This script only places items on tracks. No volume adjustments, plugin settings, markers, et cetera will be converted.
#
# This should work on MacOS and Linux.
# 
# Usage: Open Terminal, navigate to folder containing the script and before first run enter:
# chmod +x edl_to_samplitude-edl.sh
# To convert the EDL file my-file.edl enter:
# edl_to_samplitude-edl.sh my-file.edl
#
# Revision history :
# 06. Mar 2019 - v0.9 - creation by Thomas Reintjes
#
#
##############################################################################################################################################

#settings
gap=3 #seconds of silence between clips

#command line variables
inputfile="$1"

#output
outputfile="${1%.*}.samplitude.edl"
outputpath="${1%/*}"

#look for file names and write header to output file
awk -v outputpath="$outputpath" '
BEGIN {
  number_of_files=0;
  printf("Samplitude EDL File Format Version 1.5\nTitle: \"converted from EDL\"\nSample Rate: \nOutput Channels: \n\n");
  }
/FROM.CLIP.NAME/ && !seen[substr($0,index($0,$5))] {    #substring of $0 starting at $5 (file names may contain spaces)
  ++seen[substr($0,index($0,$5))];
  number_of_files+=1;
  files[number_of_files]=substr($0,index($0,$5));
}
END {
  print "Source Table Entries: " number_of_files;
  for (i in files) {
    print i " \"" outputpath "/" files[i] "\"";
  }
  for (i in files) {
    printf("\nTrack %s: \"Track %s\" Solo: 0 Mute: 0\n\n",i,i);
  }
    
}' "$inputfile" >"$outputfile"

#parse output file for file names and examine audio properties
files=$(awk '/^[0-9]* \"/ {split($0, a, "\""); $2 = a[2]; printf("%s",$2);}' "$outputfile") #split at "
# turn this into proper array:
IFS=$'\n' files=(${files})
i=1
channels_max=0 
for item in "${files[@]}" ; do    
  samplerate[$i]=$(soxi -r "$item")
  if [ "${samplerate[1]}" != "${samplerate[$i]}" ] ; then
   exit #sample rate must be the same across files
  fi
  channels=$(soxi -c "$item")
  if [ "$channels_max" -lt "$channels" ] ; then
   channels_max="$channels"
  fi
  let "i+=1"
done

#replace lines 3 and 4 in output file with values we just found
sed -i '' -e "3s/.*/Sample Rate: ${samplerate[1]}/" "$outputfile"
sed -i '' -e "4s/.*/Output Channels: $channels_max/" "$outputfile"

#convert time codes from input file and write to output file
awk -v samplerate=${samplerate[1]} -v gap=$gap '
BEGIN {
  number_of_files=0;
  count=0;
  print "#Source Track Play-In      Play-Out     Record-In    Record-Out   Vol(dB)  MT LK FadeIn       %     CurveType                          FadeOut      %     CurveType                          Name"
  print "#------ ----- ------------ ------------ ------------ ------------ -------- -- -- ------------ ----- ---------------------------------- ------------ ----- ---------------------------------- -----"

}

/[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2}/ {
#line contains time code
    playin=((substr($7,1,2) * 3600) + (substr($7,4,2) * 60) + substr($7,7,2) + (substr($7,10,2) * 0.04))*samplerate + samplerate*count*gap;
    playout=((substr($8,1,2) * 3600) + (substr($8,4,2) * 60) + substr($8,7,2) + (substr($8,10,2) * 0.04))*samplerate + samplerate*count*gap;
    recin=((substr($5,1,2) * 3600) + (substr($5,4,2) * 60) + substr($5,7,2) + (substr($5,10,2) * 0.04))*samplerate;
    recout=((substr($6,1,2) * 3600) + (substr($6,4,2) * 60) + substr($6,7,2) + (substr($6,10,2) * 0.04))*samplerate;
    count+=1;
    getline;
    thisfile=0;
        # look for the file in our list of files
		for (i=1; i<=number_of_files; i++) {
            # is the file known?
			if (filename[i] == substr($0,index($0,$5))) {
                # found it - remember where the file is
				thisfile=i;
			}
		}
		if (thisfile == 0) {
        # found a new file
			filename[++number_of_files]=substr($0,index($0,$5));
			thisfile=number_of_files;
			}    
    printf("%7s %5s %12d %12d %12d %12d      0.0  0  0            0     0                         \"*default\"            0     0                         \"*default\" \"%s\"\n",thisfile,thisfile,playin,playout,recin,recout,filename[thisfile]);
    next;
    }

{next;}' "$inputfile" >>"$outputfile"