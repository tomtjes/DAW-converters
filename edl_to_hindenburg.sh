#!/bin/bash
#
# edl_to_hindenburg.sh
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
# chmod +x edl_to_hindenburg.sh
# To convert the EDL file my-file.edl enter:
# edl_to_hindenburg.sh my-file.edl
#
# Revision history :
# 06. Mar 2019 - v0.9 - creation by Thomas Reintjes
#
#
##############################################################################################################################################

#settings
gap=3 #seconds of silence between clips on track 2

#command line variables
inputfile="$1"

#output
outputfile="${1%.*}.nhsx"
outputpath="${1%/*}"
project="${1%.*}"
project="${project##*/}"
outputfolder="$project Files"

mkdir -p "$outputpath/$outputfolder"

#look for file names and write header to output file
awk -v outputpath="$outputpath" -v outputfolder="$outputfolder" '
BEGIN {
  number_of_files=0;
  printf("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Session Samplerate=\"\">\n <AudioPool Path=\"%s\" Location=\"%s\">\n",outputfolder,outputpath);
  }
/FROM.CLIP.NAME/ && !seen[substr($0,index($0,$5))] {
  filename=substr($0,index($0,$5));
  ++seen[filename];
  number_of_files+=1;
  printf("  <File Id=\"%s\" Name=\"%s\">\n   <MetaData OriginalPath=\"%s/%s\"/>\n  </File>\n",number_of_files,filename,outputpath,filename);
}
END {
  print " </AudioPool>";
}' "$inputfile" >"$outputfile"

#parse output file for file names and examine audio properties
files=$(grep '<File Id=' "$outputfile" | sed 's# *<File Id="[0-9]*" Name="\(.*\)">#\1#g')
# turn this into proper array:
IFS=$'\n' files=(${files})
i=1
for item in "${files[@]}" ; do    
  samplerate[$i]=$(soxi -r "$outputpath/$item")
  if [ "${samplerate[1]}" != "${samplerate[$i]}" ] ; then
   exit #sample rate must be the same across files
  fi
  cp "$outputpath/$item" "$outputpath/$outputfolder/$item"
  let "i+=1"
done

#replace line 2 in output file with sample rate value
sed -i '' -e "2s/.*/<Session Samplerate=\"${samplerate[1]}\">/" "$outputfile"

# First track has all items from EDL at their original position on the timeline
awk '
BEGIN {
  number_of_files=0;
  print " <Tracks>";
  print "  <Track Name=\"Timeline\">";
  }
/[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2}/ {
#line contains time code
    recin=((substr($5,1,8) * 3600) + (substr($5,4,2) * 60) + substr($5,7,2) + (substr($5,10,2) * 0.04));
    recout=((substr($6,1,2) * 3600) + (substr($6,4,2) * 60) + substr($6,7,2) + (substr($6,10,2) * 0.04));
    # above conversion to seconds necessary to determine length:
    sec=(recout-recin);
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
    printf("   <Region Ref=\"%s\" Name=\"%s\" Start=\"%.3f\" Length=\"%.3f\" Offset=\"%.3f\" />\n",thisfile,filename[thisfile],recin,sec,recin);
    next;
    }
{next;}
END {
  print "  </Track>";
}
' "$inputfile" >>"$outputfile"

# Add track with all items in a fixed distance ($gap)
awk -v gap=$gap '
BEGIN {
  number_of_files=0;
  count=0;
  print "  <Track Name=\"Condensed\">";
  }
/[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2}/ {
#line contains time code
    playin=((substr($7,1,2) * 3600) + (substr($7,4,2) * 60) + substr($7,7,2) + (substr($7,10,2) * 0.04));
    playout=((substr($8,1,2) * 3600) + (substr($8,4,2) * 60) + substr($8,7,2) + (substr($8,10,2) * 0.04));
    # above conversion to seconds necessary to determine length:
    sec=(playout-playin);
    recin=substr($5,1,8)"."(substr($5,10,2) * 4);
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
    playin=((playin + gap * count));
    count+=1;
    printf("   <Region Ref=\"%s\" Name=\"%s\" Start=\"%.3f\" Length=\"%.3f\" Offset=\"%.3f\" />\n",thisfile,filename[thisfile],playin,sec,recin);
    next;
    }
{next;}
END {
  print "  </Track>";
  print "  <Track Name=\"Track 3\"/>";
  print "  <Track Name=\"Track 4\"/>";
  print " </Tracks>";
}
' "$inputfile" >>"$outputfile"

#Clipboard
awk '
BEGIN {
  number_of_files=0;
  count=0;
  print " <Clipboard>";
  print "  <Group Caption=\"Converted from EDL\">"
  }
/[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2}/ {
#line contains time code
    recin=((substr($5,1,8) * 3600) + (substr($5,4,2) * 60) + substr($5,7,2) + (substr($5,10,2) * 0.04));
    recout=((substr($6,1,2) * 3600) + (substr($6,4,2) * 60) + substr($6,7,2) + (substr($6,10,2) * 0.04));
    # above conversion to seconds necessary to determine length:
    sec=(recout-recin);
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
    count+=1;
    printf("   <Region Ref=\"%s\" Name=\"%02d %s\" Length=\"%.3f\" Offset=\"%.3f\" />\n",thisfile,count,filename[thisfile],sec,recin);
    next;
    }
{next;}
END {
print "  </Group>";
print "  <Group Caption=\"Group 2\"/>";
print "  <Group Caption=\"Group 3\"/>";
print "  <Group Caption=\"Group 4\"/>";
print " </Clipboard>";
print "</Session>";
}
' "$inputfile" >>"$outputfile"