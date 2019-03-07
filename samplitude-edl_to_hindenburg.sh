#!/bin/bash
#
# samplitude-edl_to_hindenburg.sh
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
# chmod +x samplitude-edl_to_hindenburg.sh
# To convert the EDL file my-samplitude.edl enter:
# samplitude-edl_to_hindenburg.sh my-samplitude.edl
#
# Revision history :
# 06. Mar 2019 - v0.9 - creation by Thomas Reintjes
#
#
##############################################################################################################################################

#command line variables
inputfile="$1"

#output
outputfile="${1%.*}.nhsx"
outputpath="${1%/*}"
project="${1%.*}"
project="${project##*/}"
outputfolder="$project Files"

#functions
urldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }

#look for file names and write header to output file
awk -v outputpath="$outputpath" -v outputfolder="$outputfolder" '
/^Sample Rate:/ {
  printf("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Session Samplerate=\"%s\">\n <AudioPool Path=\"%s\" Location=\"%s\">\n",$3,outputfolder,outputpath);
  }
/^Source Table Entries:/ {
  number_of_files=$4;
  for (i=1; i<=number_of_files; i++) {
    getline;
    split($0, a, "\"");
    originalpath = a[2];
    n = split(originalpath, b, "/")
    filename=b[n]
    printf("  <File Id=\"%s\" Name=\"%s\">\n   <MetaData OriginalPath=\"%s\"/>\n  </File>\n",$1,filename,originalpath);
	}
  }
{next;}
END {
  print " </AudioPool>";
  print " <Tracks>";
}' "$inputfile" >"$outputfile"

# figure out how many tracks there are and get their names
tracks=$(awk '/^Track [0-9]/ {count++;} END {print count;}' "$inputfile")
i=1
while [ $i -le $tracks ]; do
  pattern="^Track $i:"
  trackname[$i]="$(awk -v pattern="$pattern" '$0~pattern{split($0, a, "\"");$3 = a[2];print $3;}' "$inputfile")"
  let "i+=1"
done

# print tracks
i=1
while [ $i -le $tracks ]; do
  this_trackname="${trackname[$i]}"
  awk -v tracknumber=$i -v trackname="$this_trackname" '
  BEGIN {
    print "  <Track Name=\""trackname"\">";
    }
  /^Sample Rate:/ { samplerate=$3; }
  NF>10 {
  #more than 10 fields in line
    if ($2==tracknumber) {
      ref=$1
      playin=(($3 / samplerate));
      recin=(($5 / samplerate));
      recout=(($6 / samplerate));
      sec=(recout-recin);
      n = split($0, a, "\"");
      regionname=a[((n-1))];
      printf("   <Region Ref=\"%s\" Name=\"%s\" Start=\"%.3f\" Length=\"%.3f\" Offset=\"%.3f\" />\n",ref,regionname,playin,sec,recin);
      next;
      }
   }
  {next;}
  END {
    print "  </Track>";
  }
  ' "$inputfile" >>"$outputfile"
  let "i+=1"
done

# Hindenburg's default is 4 tracks, so let's make sure we have at least 4
if [ $tracks -lt 4 ] ; then
  i=$tracks
  until [ $i -eq 4 ] ; do
    let "i+=1"
    printf "  <Track Name=\"Track %s\" />\n" "$i" >>"$outputfile"
  done
fi

printf " </Tracks>\n <Clipboard>\n" "" >>"$outputfile"

# Same procedure again, except this time put items on clipboard groups instead of tracks
i=1
while [ $i -le $tracks ]; do
  this_trackname="${trackname[$i]}"
  awk -v tracknumber=$i -v trackname="$this_trackname" '
  BEGIN {
    count=0
    print "  <Group Caption=\""trackname"\">";
    }
  /^Sample Rate:/ { samplerate=$3; }
  NF>10 {
  #more than 10 fields in line
    if ($2==tracknumber) {
      ref=$1
      playin=(($3 / samplerate));
      recin=(($5 / samplerate));
      recout=(($6 / samplerate));
      sec=(recout-recin);
      n = split($0, a, "\"");
      regionname=a[((n-1))];
      count+=1;
      printf("   <Region Ref=\"%s\" Name=\"%02d %s\" Length=\"%.3f\" Offset=\"%.3f\" />\n",ref,count,regionname,sec,recin);
      next;
      }
   }
  {next;}
  END {
    print "  </Group>";
  }
  ' "$inputfile" >>"$outputfile"
  let "i+=1"
done

# 4 is the magic number
if [ $tracks -lt 4 ] ; then
  i=$tracks
  until [ $i -eq 4 ] ; do
    let "i+=1"
    printf "  <Group Caption=\"Group %s\" />\n" "$i" >>"$outputfile"
  done
fi

printf " </Clipboard>\n</Session>\n" "" >>"$outputfile"

#re-format output
tmp=$(sed 's#file:///#/#g' "$outputfile")
urldecode "$tmp" > "$outputfile"

#parse output file for file names and copy files to folder
files=$(grep '<MetaData OriginalPath=' "$outputfile" | sed 's# *<MetaData OriginalPath="\(.*\)"/>#\1#g')
# turn this into array:
IFS=$'\n' files=(${files})
#copy files to Hindenburg folder
mkdir -p "$outputpath/$outputfolder"
for item in "${files[@]}" ; do     
  # make sure items come with a path
  if [[ "${item%/*}" != /** ]] ; then
    item="$outputpath/$item"
  fi
  cp "$item" "$outputpath/$outputfolder/$(basename -- "$item")"
done
