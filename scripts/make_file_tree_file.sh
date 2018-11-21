#!/bin/bash
# run this from the project root
# it generates ./file_tree.txt, which is used by the cloud cli to download the files
# to the ansible controller


# set -x
# set -v

OUTPUT_FILE=${1:-file_tree.txt}
> $OUTPUT_FILE # empty out output file

#
# loop over the current directory and subdirectories
# exclude all hidden (dot) files
# exclude this file and the outputfile
# and exclude other project files are not needed on the ansible controller
#
while read line; do
    file=${line:2} # chop off "./"
	chmod_attr="$(stat --format '%a' "$file")"
	echo "${file}|${chmod_attr}">>"$OUTPUT_FILE"
done <<< "$(find . -type f -regextype posix-extended \
               ! -regex "(^\./|.*/)\..*" \
               ! -path "./${BASH_SOURCE[0]}" \
               ! -path "./${OUTPUT_FILE}" \
               ! -regex "(./|.*/)[LNR].*"\
               ! -path "./doc/*"\
               ! -path "./images/*"\
               ! -path "./ci*/*"\
               ! -path "./templates/*"\
            )"

