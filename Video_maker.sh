#!/bin/bash
set -o nounset # set -u (exits, if you try to use an uninitialized variable)
set -o errexit # set -e (exits, if any statement returns a non-true value)

# Usage: script <text-file> <audio-file>

# Input text-file should have header (audio delay) and text separated by two-newlines for every separate image.
# Sample file given below

# AUDIO_START_TIME: 3 # audio delay in seconds
#
# TIME: 3 # duration of this text/picture in the output video, in sec
# This is a sample file and this text 
# will be on image-1
#
# TIME: 12.7 # duration of this text/picture in the output video, in sec
# IMAGE: image-2.jpg # direct image file
#
# TIME: 102.4 # duration of this text/picture in the output video, in sec
# IMAGE: image-3.jpg
#
# TIME: 7.0 # duration of this text/picture in the output video, in sec
# This text will be on image-4

OUTPUT_HEIGHT=1080 # 1080p (16:9 aspect ratio is used)

# Need not change below this line
TEXT_FONT_SIZE=100 # font size
OUTPUT_WIDTH=$((((${OUTPUT_HEIGHT}*16)+8)/9)) # 16:9 aspect-ratio (height adjusted to be divisible by 9)
INP_FILE="$1"
AUDIO_FILE="$2"

# read text-file and split into blocks to convert into separate image
# See: http://stackoverflow.com/questions/16897092/split-on-multiple-newline-characters-in-bash
inp_data=$(<"${INP_FILE}")                  # read file into string
inp_data=${inp_data//$'\n'$'\n'/$'\t'};     # 2 newlines to 1 tab
while [[ "$inp_data" =~ $'\t'$'\n' ]] ; do
  inp_data=${inp_data//$'\t'$'\n'/$'\t'};   # eat up further newlines
done
inp_data=${inp_data//$'\t'$'\t'/$'\t'};     # sqeeze tabs
IFS=$'\t'                                   # field separator is now tab
arrINP=( $inp_data );                       # slit into array

# generate images from the text-files
MAX_HEIGHT_REF=0 # initialize
MAX_WIDTH_REF=0 # initialize
MAX_HEIGHT_TXT=0 # initialize
MAX_WIDTH_TXT=0 # initialize
PIC_TIME_DURATIONS=() # initialize: array for duration of this text/picture in the output video, in sec
AUDIO_START_TIME=0 # initialize
indx=0
for txt_block in ${arrINP[@]}; do
    ((++indx))
    if [ ${indx} == 1 ];then # read header
        # check 1st word on 1st line, for audio delay info
        if [[ $(echo ${txt_block} | sed -n 1p | awk '{print $1;}') != "AUDIO_START_TIME:" ]];then #
            echo "error: No Audio delay info"; exit 1;
        fi
        AUDIO_START_TIME=$(echo ${txt_block} | sed -n 1p | awk '{print $2}') # extract audio delay, in sec
        continue
    fi
    SUFFIX="$( printf '%04d' $indx )" # translate indx as 4-digit string for SUFFIX
    if [[ $(echo ${txt_block} | head -n1 | awk '{print $1;}') != "TIME:" ]];then # check 1st word, if no time info
        echo "error: No Time info"; exit 1;
    fi
    time=$(echo ${txt_block} | sed -n 1p | awk '{print $2}') # extract time info, in sec
    PIC_TIME_DURATIONS+=(${time}) # append to array
    txt_block=$(echo ${txt_block} | sed 1d) # delete the 1st line
    if [[ $(echo ${txt_block} | sed -n 1p | awk '{print $1;}') == "IMAGE:" ]];then # check 1st word, for direct-reference-images 
        ref_img_file=$(echo ${txt_block} | sed -n 1p | awk '{print $2}')
        convert ${ref_img_file} -quality 100 -resize x${OUTPUT_HEIGHT}\> "tmp-image-${SUFFIX}-ref.png"
        #convert ${ref_img_file} "tmp-image-${SUFFIX}-ref.png"
        W=$(identify "tmp-image-${SUFFIX}-ref.png" | cut -f 3 -d " " | sed s/x.*//) # width of image
        H=$(identify "tmp-image-${SUFFIX}-ref.png" | cut -f 3 -d " " | sed s/.*x//) # height of image
        MAX_WIDTH_REF=$(($W>${MAX_WIDTH_REF}?$W:${MAX_WIDTH_REF})) # max width of all images
        #MAX_HEIGHT_REF=$(($H>${MAX_HEIGHT_REF}?$H:${MAX_HEIGHT_REF})) # max height of all images 
    else # for text, convert to images (text-images)
        # remove leading and trailing spaces from each line of text, also replace multiple spaces with one space
        txt_block=$(echo "${txt_block}" | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e 's/[[:space:]]\+/ /g')
        # create image from text 
        PANGO_TXT=" <span foreground=\"black\" font=\"${TEXT_FONT_SIZE}\">${txt_block}</span> "
        echo "${PANGO_TXT}" | convert pango:@- -quality 100 tmp-${SUFFIX}-txt.pnm
        #potrace --pgm tmp-textimage.pnm --height ${OUTPUT_HEIGHT} -o "${SUFFIX}-txt.pbm"
        # pre-process image by mkbitmap for better tracing
        #mkbitmap tmp-textimage.pnm -o tmp-textimage-bitmap.pnm
        #mv tmp-textimage-bitmap.pnm tmp-textimage.pnm 
        # trace the image to generate a vector-graphic file
        potrace --svg tmp-${SUFFIX}-txt.pnm -o tmp-${SUFFIX}-txt.svg
        # generate the output image
        inkscape tmp-${SUFFIX}-txt.svg --export-png="tmp-image-${SUFFIX}-txt.png" >/dev/null
        W=$(identify "tmp-image-${SUFFIX}-txt.png" | cut -f 3 -d " " | sed s/x.*//) # width of image
        H=$(identify "tmp-image-${SUFFIX}-txt.png" | cut -f 3 -d " " | sed s/.*x//) # height of image
        MAX_WIDTH_TXT=$(($W>${MAX_WIDTH_TXT}?$W:${MAX_WIDTH_TXT})) # max width of all images
        MAX_HEIGHT_TXT=$(($H>${MAX_HEIGHT_TXT}?$H:${MAX_HEIGHT_TXT})) # max height of all images 
    fi
done

# for direct-reference-images: adjusting max-height to accommodate max-width
MAX_HEIGHT_REF=${OUTPUT_HEIGHT}
# values adjusted to yeild integer after division
MAX_HEIGHT_REF=$(($((((${MAX_HEIGHT_REF}*16)+8)/9))>${MAX_WIDTH_REF}?${MAX_HEIGHT_REF}:$((((${MAX_WIDTH_REF}*9)+15)/16))))
# generating a matching 16:9 white background
convert -size $((((${MAX_HEIGHT_REF}*16)+8)/9))x${MAX_HEIGHT_REF} xc:white tmp-white-background-ref.png

# for text-images: adjusting max-height to accommodate max-width
# values adjusted to yeild integer after division
MAX_HEIGHT_TXT=$(($((((${MAX_HEIGHT_TXT}*16)+8)/9))>${MAX_WIDTH_TXT}?${MAX_HEIGHT_TXT}:$((((${MAX_WIDTH_TXT}*9)+15)/16))))
# generating a matching 16:9 white background
convert -size $((((${MAX_HEIGHT_TXT}*16)+8)/9))x${MAX_HEIGHT_TXT} xc:white tmp-white-background-txt.png

# mapping the image on a matching background to generate an image with uniform text-size and uniform dimentions
TOTAL_VIDEO_DURATION=0
indx=0
for imagefile in tmp-image-*.png; do
    SUFFIX=${imagefile#tmp-image-}; SUFFIX=${SUFFIX%.*}
    if [[ $imagefile == *"-ref.png" ]];then # for direct-reference-images 
        composite -gravity center "${imagefile}" tmp-white-background-ref.png "tmp-overllaped-image-${SUFFIX}.png"
    else # for text-images
        composite -gravity center "${imagefile}" tmp-white-background-txt.png "tmp-overllaped-image-${SUFFIX}.png"
    fi
    convert "tmp-overllaped-image-${SUFFIX}.png" -resize ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}\! "tmp-final-image-${SUFFIX}.png"
    #VIDEO_DURATION=$(echo | awk "{print ${TIME_STAMPS[$((${indx}+1))]}-${TIME_STAMPS[$indx]}}")
    VIDEO_DURATION=${PIC_TIME_DURATIONS[$indx]}
    ffmpeg -loglevel error -y -loop 1 -i tmp-final-image-${SUFFIX}.png -r 60 -c:v libopenh264 -qp 0 -pix_fmt yuv420p -t ${VIDEO_DURATION} tmp-segment-${SUFFIX}.mp4
    ((++indx))
done

# generate video & add audio
echo "Concating ..."
ffmpeg -loglevel error -y -f concat -safe 0 -i <(for f in tmp-segment-*.mp4; do echo "file '$PWD/$f'"; done) -c copy tmp-only-video.mkv
echo "Adding Audio ..."
ffmpeg -loglevel error -y -i tmp-only-video.mkv -itsoffset ${AUDIO_START_TIME} -i ${AUDIO_FILE} -c copy output.mkv

# remove temporary files
rm -rf tmp-*

# Successful completion:
exit 0
# EOF

