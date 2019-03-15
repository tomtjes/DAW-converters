#!/usr/bin/awk -f
#
# edl_to_samplitude-edl.awk
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
# chmod +x edl_to_samplitude-edl.awk
# To convert the EDL file my-file.edl enter:
# edl_to_samplitude-edl.awk my-file.edl
#
# Revision history :
# 13. Mar 2019 - v0.9 - creation by Thomas Reintjes
#
#
##############################################################################################################################################

BEGIN {
  #settings
  gap=3 #seconds of silence between clips on track 2
  
  #prepare output
  inputfile = ARGV[1]
  cmd="dirname \""inputfile"\""
  cmd | getline outputpath
  if (outputpath == "") outputpath=ENVIRON["PWD"]
  cmd="basename \""inputfile"\" .edl"
  cmd | getline project
  outputfile=outputpath"/"project"-samplitude.edl"
  
  number_of_files=0
  number_of_items=0
  lastrate=0
  channels_max=0
}

/FROM.CLIP.NAME/ {
  number_of_items++
  thisfile=substr($0,index($0,$5))
  if (!seen[thisfile]) {
    number_of_files++
    seen[thisfile]=number_of_files
    filename[number_of_files]=thisfile
    cmd="soxi -r \""outputpath"/"thisfile"\""
    cmd | getline samplerate
    if (lastrate!=0 && samplerate!=lastrate) {
        print "WARNING: all sample rates must be identical" > "/dev/stderr"
        exit
    }
    lastrate=samplerate
    cmd="soxi -c \""outputpath"/"thisfile"\""
    cmd | getline channels
    if (channels_max < channels)
      channels_max=channels
  }
  fileID[number_of_items]=seen[thisfile]
  $0=lastLine
  #convert timecodes to seconds
  playin[number_of_items]=((substr($7,1,2) * 3600) + (substr($7,4,2) * 60) + substr($7,7,2) + (substr($7,10,2) * 0.04))*samplerate 
  playout[number_of_items]=((substr($8,1,2) * 3600) + (substr($8,4,2) * 60) + substr($8,7,2) + (substr($8,10,2) * 0.04))*samplerate
  recin[number_of_items]=((substr($5,1,2) * 3600) + (substr($5,4,2) * 60) + substr($5,7,2) + (substr($5,10,2) * 0.04))*samplerate
  recout[number_of_items]=((substr($6,1,2) * 3600) + (substr($6,4,2) * 60) + substr($6,7,2) + (substr($6,10,2) * 0.04))*samplerate
}

# to be able to reference line with timecodes in following line with filename, save it:
{ lastLine=$0 }

END {	
  printf("Samplitude EDL File Format Version 1.5\nTitle: \"converted from EDL\"\nSample Rate: %s\nOutput Channels: %s\n\n",samplerate,channels_max) >outputfile
  print "Source Table Entries: " number_of_files >outputfile
  for (i in filename) {
    print i " \"" outputpath "/" filename[i] "\"" >outputfile
  }
  if ( number_of_files == 1) {
    printf("\nTrack 1: \"Timeline\" Solo: 0 Mute: 0") >outputfile
    printf("\nTrack 2: \"Condensed\" Solo: 0 Mute: 0") >outputfile
  }
  else {
    for (i in filename) {
      printf("\nTrack %s: \"%s\" Solo: 0 Mute: 0",i,filename[i]) >outputfile
    }
  }
  print "\n\n#Source Track Play-In      Play-Out     Record-In    Record-Out   Vol(dB)  MT LK FadeIn       %     CurveType                          FadeOut      %     CurveType                          Name" >outputfile
  print "#------ ----- ------------ ------------ ------------ ------------ -------- -- -- ------------ ----- ---------------------------------- ------------ ----- ---------------------------------- -----" >outputfile
  for (i=1; i<=number_of_items; i++) {
    printf("%7s %5s %12d %12d %12d %12d      0.0  0  0            0     0                         \"*default\"            0     0                         \"*default\" \"%s\"\n",fileID[i],fileID[i],recin[i],recout[i],recin[i],recout[i],filename[fileID[i]]) >outputfile
  }
  if ( number_of_files == 1) {
    for (i=1; i<=number_of_items; i++) {
      playin[i]=playin[i]+samplerate*(i-1)*gap
      playout[i]=playout[i]+samplerate*(i-1)*gap
      printf("%7s %5s %12d %12d %12d %12d      0.0  0  0            0     0                         \"*default\"            0     0                         \"*default\" \"%s\"\n",1,2,playin[i],playout[i],recin[i],recout[i],filename[fileID[i]]) >outputfile
    }
  }
}