#!/usr/bin/awk -f
#
# edl_to_hindenburg.awk
# converts an EDL (Edit Decision List) file to a Hindenburg Session file 
#
# Tools exporting EDL include Trint
#
# This script only places items on tracks. No volume adjustments, plugin settings, markers, et cetera will be converted.
# The first track will contain items at their original position on the timeline.
# The second track will contain the items spaced out evenly. (Set the width of the gap below)
# All items will also be available on the clipboard.
#
# This should work on MacOS and Linux.
# 
# Usage: Open Terminal, navigate to folder containing the script and before first run enter:
# chmod +x edl_to_hindenburg.awk
# To convert the EDL file my-file.edl enter:
# edl_to_hindenburg.awk /path/to/my-file.edl
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
  outputfolder=project" Files"
  cmd="mkdir -p \""outputpath"/"outputfolder"\""
  cmd | getline tmp
  outputfile=outputpath"/"project".nhsx"
  
  number_of_files=0
  number_of_items=0
  lastrate=0
}

/[0-9][0-9]:[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ {
#line contains time code
  number_of_items++
  #convert timecodes to seconds
  recin[number_of_items]=((substr($5,1,2) * 3600) + (substr($5,4,2) * 60) + substr($5,7,2) + (substr($5,10,2) * 0.04))
  recout[number_of_items]=((substr($6,1,2) * 3600) + (substr($6,4,2) * 60) + substr($6,7,2) + (substr($6,10,2) * 0.04))
  playin[number_of_items]=((substr($7,1,2) * 3600) + (substr($7,4,2) * 60) + substr($7,7,2) + (substr($7,10,2) * 0.04))
  #(not used) playout[number_of_items]=((substr($8,1,2) * 3600) + (substr($8,4,2) * 60) + substr($8,7,2) + (substr($8,10,2) * 0.04))
  seconds[number_of_items]=(recout[number_of_items]-recin[number_of_items])
  #get next line, and check if file name in it has been seen before
  getline
  thisfile=substr($0,index($0,$5))
  if (!seen[thisfile]) {
    number_of_files++
    seen[thisfile]=number_of_files
    filename[number_of_files]=thisfile
    cmd="cp \""outputpath"/"thisfile"\" \""outputpath"/"outputfolder"/"thisfile"\""
    cmd | getline tmp
    cmd="soxi -r \""outputpath"/"thisfile"\""
    cmd | getline samplerate
    if (lastrate!=0 && samplerate!=lastrate) {
        print "WARNING: all sample rates must be identical" > "/dev/stderr"
        exit
    }
    lastrate=samplerate
  }
  fileID[number_of_items]=seen[thisfile]
}
{next;}
END {	
  printf("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Session Samplerate=\"%s\">\n",lastrate) >outputfile	
  printf(" <AudioPool Path=\"%s\" Location=\"%s\">\n",outputfolder,outputpath) >outputfile 
  for (i=1; i<=number_of_files; i++) {
    printf("  <File Id=\"%s\" Name=\"%s\">\n   <MetaData OriginalPath=\"%s/%s\"/>\n  </File>\n",i,filename[i],outputpath,filename[i]) >outputfile
  }
  print " </AudioPool>" >outputfile
  print " <Tracks>" >outputfile
  if (number_of_files==1) {
    # First track has all items from EDL at their original position on the timeline
    print "  <Track Name=\"Timeline\">" >outputfile
    for (i=1; i<=number_of_items; i++) {
      printf("   <Region Ref=\"%s\" Name=\"%s\" Start=\"%.3f\" Length=\"%.3f\" Offset=\"%.3f\" />\n",fileID[i],filename[fileID[i]],recin[i],seconds[i],recin[i]) >outputfile
    }
    print "  </Track>" >outputfile
    # Add track with all items in a fixed distance (gap)
    print "  <Track Name=\"Condensed\">" >outputfile
    for (i=1; i<=number_of_items; i++) {
      newplayin=((playin[i] + (i-1) * gap))
      printf("   <Region Ref=\"%s\" Name=\"%s\" Start=\"%.3f\" Length=\"%.3f\" Offset=\"%.3f\" />\n",fileID[i],filename[fileID[i]],newplayin,seconds[i],recin[i]) >outputfile
    }
    print "  </Track>" >outputfile
  }
  else {
    #if more than 1 audio file, add one track for each file
    for (j=1; j<=number_of_files; j++) {
      printf("  <Track Name=\"%s\">\n",filename[j]) >outputfile
      for (i=1; i<=number_of_items; i++) {
        if (fileID[i]==j) {
          printf("   <Region Ref=\"%s\" Name=\"%s\" Start=\"%.3f\" Length=\"%.3f\" Offset=\"%.3f\" />\n",fileID[i],filename[fileID[i]],recin[i],seconds[i],recin[i]) >outputfile
        }
      }
      print "  </Track>" >outputfile
    }
  }
  # Hindenburg likes to have 4 tracks or more
  for (i=number_of_files+1; i<=4; i++) {
    printf("  <Track Name=\"Track %s\"/>\n",i) >outputfile
  }
  print " </Tracks>" >outputfile
  print " <Clipboard>" >outputfile
  for (j=1; j<=number_of_files; j++) {
    printf("  <Group Caption=\"Clips Track %s\">\n",j) >outputfile
    for (i=1; i<=number_of_items; i++) {
      if (fileID[i]==j) {
        printf("   <Region Ref=\"%s\" Name=\"%02d %s\" Length=\"%.3f\" Offset=\"%.3f\" />\n",fileID[i],i,filename[fileID[i]],seconds[i],recin[i]) >outputfile
      }
    }
    print "  </Group>" >outputfile
  }
  # Hindenburg likes to have 4 clipboard groups or more
  for (i=number_of_files+1; i<=4; i++) {
    printf("  <Group Caption=\"Group %s\"/>\n",i) >outputfile
  }
  print " </Clipboard>" >outputfile
  print "</Session>" >outputfile
}
