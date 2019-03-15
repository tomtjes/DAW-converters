#!/usr/bin/awk -f
#
# samplitude-edl_to_hindenburg.awk
# converts a Samplitude EDL file to a Hindenburg Session file 
#
# Tools exporting Samplitude EDL include Reaper, Descript
# 
# This script only places items on tracks. No volume adjustments, plugin settings, markers, et cetera will be converted.
# Items from tracks will also be copied to corresponding Hindenburg clipboard groups.
#
# This should work on MacOS and Linux.
# 
# Usage: Open Terminal, navigate to folder containing the script and before first run enter:
# chmod +x samplitude-edl_to_hindenburg.awk
# To convert the EDL file my-samplitude.edl enter:
# samplitude-edl_to_hindenburg.awk my-samplitude.edl
#
# Revision history :
# 13. Mar 2019 - v0.9 - creation by Thomas Reintjes
#
#
##############################################################################################################################################


BEGIN {  
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
  number_of_tracks=0
}

/^Sample Rate:/ {samplerate=$3}

/^Source Table Entries:/ {
  number_of_files=$4;
  for (i=1; i<=number_of_files; i++) {
    getline;
    file_number=$1
    #urldecode
    for (y=0;y<255;y++) if (y!=37) gsub(sprintf("%%%02x|%%%02X",y,y), y==38 ? "\\&" : sprintf("%c", y), $0);gsub(/%25/, "%", $0);
    #find quoted filenames
    split($0, a, "\"");
    originalpath[file_number] = a[2];
    #remove file://
    if (originalpath[file_number] ~ /file:/) originalpath[file_number]=substr(originalpath[file_number],8)
    #separate filename from rest of path
    n = split(originalpath[file_number], b, "/")
    filename[file_number]=b[n]
    cmd="cp \""originalpath[file_number]"\" \""outputpath"/"outputfolder"/"filename[file_number]"\""
    cmd | getline tmp
	}
  }
  
/^Track [0-9]/ {
  number_of_tracks++
  track_number=substr($2,1,length($2)-1)
  split($0, a, "\"")
  trackname[track_number] = a[2]
  }
  
NF>10 && /^ *[0-9]/ {
  #more than 10 fields in line that starts with digit
  number_of_items++
  trackID[number_of_items]=$2
  fileID[number_of_items]=$1
  playin[number_of_items]=($3 / samplerate)
  recin[number_of_items]=($5 / samplerate)
  recout[number_of_items]=($6 / samplerate)
  seconds[number_of_items]=(recout[number_of_items]-recin[number_of_items])
  n=split($0, a, "\"")
  regionname[number_of_items]=a[n-1]
  }

{next;}

END {
  printf("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Session Samplerate=\"%s\">\n <AudioPool Path=\"%s\" Location=\"%s\">\n",samplerate,outputfolder,outputpath) >outputfile
  for (i=1; i<=number_of_files; i++) {
    printf("  <File Id=\"%s\" Name=\"%s\">\n   <MetaData OriginalPath=\"%s\"/>\n  </File>\n",i,filename[i],originalpath[i]) >outputfile
  }
  print " </AudioPool>" >outputfile
  print " <Tracks>" >outputfile
  for (j=1; j<=number_of_tracks; j++) {
    printf("  <Track Name=\"%s\">\n",trackname[j]) >outputfile
    for (i=1; i<=number_of_items; i++) {
        if (trackID[i]==j) {
          printf("   <Region Ref=\"%s\" Name=\"%s\" Start=\"%.3f\" Length=\"%.3f\" Offset=\"%.3f\" />\n",fileID[i],regionname[i],playin[i],seconds[i],recin[i]) >outputfile
        }
      }
      print "  </Track>" >outputfile
    }   
  # Hindenburg likes to have 4 tracks or more
  for (i=number_of_tracks+1; i<=4; i++) {
    printf("  <Track Name=\"Track %s\"/>\n",i) >outputfile
  }
  print " </Tracks>" >outputfile
  print " <Clipboard>" >outputfile
  for (j=1; j<=number_of_tracks; j++) {
    printf("  <Group Caption=\"Clips Track %s\">\n",j) >outputfile
    for (i=1; i<=number_of_items; i++) {
      if (trackID[i]==j) {
        printf("   <Region Ref=\"%s\" Name=\"%02d %s\" Length=\"%.3f\" Offset=\"%.3f\" />\n",fileID[i],i,regionname[i],seconds[i],recin[i]) >outputfile
      }
    }
    print "  </Group>" >outputfile
  }
  # Hindenburg likes to have 4 clipboard groups or more
  for (i=number_of_tracks+1; i<=4; i++) {
    printf("  <Group Caption=\"Group %s\"/>\n",i) >outputfile
  }
  print " </Clipboard>" >outputfile
  print "</Session>" >outputfile
}