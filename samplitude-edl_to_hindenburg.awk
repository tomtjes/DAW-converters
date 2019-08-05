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
# To convert the EDL file /path/to/my-samplitude.edl enter:
# samplitude-edl_to_hindenburg.awk /path/to/my-samplitude.edl
#
# Revision history :
# 14. Mar 2019 - v0.9 - creation by Thomas Reintjes (https://reidio.io)
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
  number_of_files=$4
  for (i=1; i<=number_of_files; i++) {
    getline
    file_number=$1
    #urldecode
    for (y=0;y<255;y++) if (y!=37) gsub(sprintf("%%%02x|%%%02X",y,y), y==38 ? "\\&" : sprintf("%c", y), $0);gsub(/%25/, "%", $0)
    #find quoted filenames
    split($0, a, "\"")
    originalpath[file_number] = a[2]
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
  playout[number_of_items]=($4 / samplerate)
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
  # Hindenburg likes to have 4+ tracks
  for (i=number_of_tracks+1; i<=4; i++) {
    printf("  <Track Name=\"Track %s\"/>\n",i) >outputfile
  }
  print " </Tracks>" >outputfile
  print " <Clipboard>" >outputfile
  for (j=1; j<=number_of_tracks; j++) {
    printf("  <Group Caption=\"Clips Track %s\">\n",j) >outputfile
    number_of_items_on_this_track=0
    for (i=1; i<=number_of_items; i++) {
      if (trackID[i]==j) itemsonthistrack[++number_of_items_on_this_track]=i
    }
    i=1
    number_of_clips=0 #count clips in this group
    while (i<=number_of_items_on_this_track) {
      number_of_clips++
      number_in_clip=0 #count items in this clip
      gap=0 #length of silence between items
      while (gap < 1 && i<=number_of_items_on_this_track) { # less than 1 second gap means items are one clip
        this_item=itemsonthistrack[i]
        itemsinthisclip[++number_in_clip]=this_item #increase count of items in clip and save item to clip
        next_item=itemsonthistrack[++i] #this is where i goes up!
        gap=(playin[next_item]-playout[this_item]) # seconds between items
      }
      #check if this clip contains multiple items/regions
      if (number_in_clip>1) {
        #figure out clip length
        item1=itemsinthisclip[1]
        item2=itemsinthisclip[number_in_clip]
        clip_length=(playout[item2]-playin[item1])
        printf("   <Clip Name=\"%02d %s\" Length=\"%.3f\" Mode=\"Block\">\n",number_of_clips,regionname[item1],clip_length) >outputfile
        #iterate over items in this clip
        for (k=1; k<=number_in_clip; k++) {
          item_k=itemsinthisclip[k]
          #start time is relative to first item
          start_k=(playin[item_k]-playin[item1])
          printf("    <Region Ref=\"%s\" Name=\"%s\" Start=\"%.3f\" Length=\"%.3f\" Offset=\"%.3f\" />\n",fileID[item_k],regionname[item_k],start_k,seconds[item_k],recin[item_k]) >outputfile
        }
        print "   </Clip>" >outputfile
      }
      else #only 1 item in clip
        printf("   <Region Ref=\"%s\" Name=\"%02d %s\" Length=\"%.3f\" Offset=\"%.3f\" />\n",fileID[this_item],number_of_clips,regionname[this_item],seconds[this_item],recin[this_item]) >outputfile
    }
    print "  </Group>" >outputfile
  }
  # Hindenburg likes to have 4+ clipboard groups
  for (i=number_of_tracks+1; i<=4; i++) {
    printf("  <Group Caption=\"Group %s\"/>\n",i) >outputfile
  }
  print " </Clipboard>" >outputfile
  print "</Session>" >outputfile
}
