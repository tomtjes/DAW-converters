#!/bin/bash
#
# hindenburg_to_samplitude-edl.sh
# converts a Hindenburg Session file to a Samplitude EDL file
#
# Tools able to import Samplitude EDL include Reaper, Samplitude
#
# This script only places items on tracks. No volume adjustments, plugin settings, markers, et cetera will be converted.
#
# This should work on MacOS and Linux, XMLStarlet is required however:
# http://xmlstar.sourceforge.net/doc/UG/xmlstarlet-ug.html
# 
# Usage: Open Terminal, navigate to folder containing the script and before first run enter:
# chmod +x hindenburg_to_samplitude-edl.sh
# To convert the Hindenburg file my-session.nhsx enter:
# hindenburg_to_samplitude-edl.sh /path/to/my-session.nhsx
#
# Revision history :
# 06. Mar 2019 - v0.9 - creation by Thomas Reintjes
#
#
##############################################################################################################################################

#settings
gap=3  #seconds between clipboard clips

#command line variables
inputfile="$1"

#output
outputfile="${1%.*}.samplitude.edl"
outputpath="${1%/*}"
if [[ "$outputpath" == "" ]] ; then
  outputpath="$PWD"
fi

#functions
#convert 00:00:00.000 timecodes into number of samples
samplify () {  
  local timecode=$1
  local milliseconds="${timecode: -3}"
  local seconds="${timecode: -6:2}"
  local minutes="${timecode: -9:2}"
  local hours="${timecode: -12:2}"
  # 10# converts it to Base10 numbers, thereby removing leading 0s and converting empty variables to 0
  local samples=$(( ((10#$hours)*3600+(10#$minutes)*60+(10#$seconds))*$samplerate+(10#$milliseconds)*$samplerate/1000 ))
  echo "$samples"
}

#examine Regions in XML
regiondata () {  
  region_data[1]=$(xmlstarlet sel -t -m ''"$1"'' -v '@Ref' -n "$inputfile")
  region_data[2]=$(xmlstarlet sel -t -m ''"$1"'' -v '@Name' -n "$inputfile")
  region_data[3]=$(xmlstarlet sel -t -m ''"$1"'' -v '@Start' -n "$inputfile")
  region_data[4]=$(xmlstarlet sel -t -m ''"$1"'' -v '@Length' -n "$inputfile")
  region_data[5]=$(xmlstarlet sel -t -m ''"$1"'' -v '@Offset' -n "$inputfile")
  region_data[3]=$(samplify "${region_data[3]}")
  region_data[4]=$(samplify "${region_data[4]}")
  region_data[5]=$(samplify "${region_data[5]}")
}

#get basic settings from Hindenburg Session
samplerate=$(xmllint --xpath 'string(/Session/@Samplerate)' "$inputfile")
folder="$(xmllint --xpath 'string(/Session/AudioPool/@Path)' "$inputfile")"
location="$(xmllint --xpath 'string(/Session/AudioPool/@Location)' "$inputfile")"

#get arrays for file IDs, files, and tracks
fileIDs=($(xmlstarlet sel -t -m '//AudioPool/File' -v '@Id' -n "$inputfile"))

filenames="$(xmlstarlet sel -t -m '//AudioPool/File' -v '@Name' -o '
' -n "$inputfile")"
# turn this into proper array:
IFS=$'\n' filenames=(${filenames})

tracks=$(xmlstarlet sel -t -m '//Tracks/Track' -v '@Name' -o '
' -n "$inputfile")
# turn this into proper array:
IFS=$'\n' tracks=(${tracks})

#determine full paths of files as well as max number of channels
i=0
channels_max=0 
for filename in "${filenames[@]}" ; do 
  if [[ $filename != /** ]] ; then
    if [[ $folder != "" ]] ; then
      filename="$folder/$filename"
    fi
    if [[ $location != "" ]] ; then
      filename="$location/$filename"
    fi
  filenames[$i]="$filename"
  fi
  channels=$(soxi -c "$filename")
  if [ "$channels_max" -lt "$channels" ] ; then
   channels_max="$channels"
  fi
  let "i+=1"
done

#print EDL header
printf "Samplitude EDL File Format Version 1.5\nTitle: \"converted from Hindenburg\"\nSample Rate: %s\nOutput Channels: %s\n\nSource Table Entries: %s\n" "$samplerate" "$channels_max" "${#filenames[@]}" > $outputfile

#print Source Table
i=1
for filename in "${filenames[@]}" ; do 
  printf "   %s \"%s\"\n" "$i" "$filename" >>$outputfile
  let "i+=1"
done

#print tracks
track_number=1
for track in "${tracks[@]}" ; do
  printf "\nTrack %s: \"%s\" Solo: 0 Mute: 0\n" "$track_number" "$track" >>$outputfile
  echo "#Source Track Play-In      Play-Out     Record-In    Record-Out   Vol(dB)  MT LK FadeIn       %     CurveType                          FadeOut      %     CurveType                          Name" >>$outputfile
  echo "#------ ----- ------------ ------------ ------------ ------------ -------- -- -- ------------ ----- ---------------------------------- ------------ ----- ---------------------------------- -----" >>$outputfile
  region_count=$(xmlstarlet sel -t -c 'count(//Track[@Name="'"$track"'"]/Region)' -n "$inputfile")
  i=1
  while [ $i -le $region_count ] ; do
    regiondata "(//Track[@Name=\"$track\"]/Region)[$i]"
    playout=$(( ${region_data[3]} + ${region_data[4]} )) # start + length
    recout=$(( ${region_data[5]} + ${region_data[4]} ))  # offset + length
    printf "%7s %5s %12s %12s %12s %12s      0.0  0  0            0     0                         \"*default\"            0     0                         \"*default\" \"%s\"\n" "${region_data[1]}" "$track_number" "${region_data[3]}" "$playout" "${region_data[5]}" "$recout" "${region_data[2]}" >>$outputfile
    let "i+=1"
  done  
  let "track_number+=1"
done

#print clipboard groups to additional tracks
clipboard=$(xmlstarlet sel -t -m '//Clipboard/Group' -v '@Caption' -o '
' -n "$inputfile")
# turn this into array:
IFS=$'\n' clipboard=(${clipboard})

for group in "${clipboard[@]}" ; do
  region_count=$(xmlstarlet sel -t -c 'count(//Group[@Caption="'"$group"'"]/Region)' -n "$inputfile")
  clip_count=$(xmlstarlet sel -t -c 'count(//Group[@Caption="'"$group"'"]/Clip)' -n "$inputfile")
  total_count=$(( $region_count + $clip_count ))
  #only create track if group has any regions or clips
  if ! [ "$total_count" -gt 0 ] ; then 
    continue
  fi
  printf "\nTrack %s: \"Clips: %s\" Solo: 0 Mute: 1\n" "$track_number" "$group" >>$outputfile
  echo "#Source Track Play-In      Play-Out     Record-In    Record-Out   Vol(dB)  MT LK FadeIn       %     CurveType                          FadeOut      %     CurveType                          Name" >>$outputfile
  echo "#------ ----- ------------ ------------ ------------ ------------ -------- -- -- ------------ ----- ---------------------------------- ------------ ----- ---------------------------------- -----" >>$outputfile

  current_region=0
  current_clip=0
  region_start=0
  i=1
  while [ $i -le $total_count ] ; do
    #check if node is a clip (if it has a Ref attribute it's not a clip)
    is_clip=$(xmlstarlet sel -t -m '(//Group[@Caption="'"$group"'"]/Region|//Group[@Caption="'"$group"'"]/Clip)['"$i"']' -i '@Ref' -o 'false' -n "$inputfile")
    #Region
    if [ "$is_clip" == false ] ; then  
      let "current_region+=1"  
      regiondata "(//Group[@Caption=\"$group\"]/Region)[$current_region]"
      playout=$(( $region_start + ${region_data[4]} ))    # start + length
      recout=$(( ${region_data[5]} + ${region_data[4]} )) # offset + length
      printf "%7s %5s %12s %12s %12s %12s      0.0  0  0            0     0                         \"*default\"            0     0                         \"*default\" \"%s\"\n" "${region_data[1]}" "$track_number" "$region_start" "$playout" "${region_data[5]}" "$recout" "${region_data[2]}" >>$outputfile 
      region_start=$(( $region_start + ${region_data[4]} + $gap * $samplerate ))
    #Clip
    else
      let "current_clip+=1" 
      clip_offset=$(xmlstarlet sel -t -m '(//Group[@Caption="'"$group"'"]/Clip)['"$current_clip"']' -v '@Start' -n "$inputfile")
      clip_offset=$(samplify $clip_offset)
      clip_length=$(xmlstarlet sel -t -m '(//Group[@Caption="'"$group"'"]/Clip)['"$current_clip"']' -v '@Length' -n "$inputfile")
      clip_length=$(samplify $clip_length)
      clip_region_count=$(xmlstarlet sel -t -c 'count(//Group[@Caption="'"$group"'"]/Clip['"$current_clip"']/Region)' -n "$inputfile")
      j=1
      while [ $j -le $clip_region_count ] ; do
        regiondata "(//Group[@Caption=\"$group\"]/Clip[$current_clip]/Region)[$j]"
        #modify region start, accounting for position on track and Clip Offset
        region_data[3]=$(( $region_start + ${region_data[3]} - $clip_offset ))
        playout=$(( ${region_data[3]} + ${region_data[4]} )) # start + length
        recout=$(( ${region_data[5]} + ${region_data[4]} ))  # offset + length
        printf "%7s %5s %12s %12s %12s %12s      0.0  0  0            0     0                         \"*default\"            0     0                         \"*default\" \"%s\"\n" "${region_data[1]}" "$track_number" "${region_data[3]}" "$playout" "${region_data[5]}" "$recout" "${region_data[2]}" >>$outputfile
        let "j+=1"
      done
      region_start=$(( $region_start + $clip_length + $gap * $samplerate ))
    fi
    let "i+=1"
  done  
  let "track_number+=1"
done