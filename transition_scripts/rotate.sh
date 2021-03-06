#!/bin/bash
#
# ffmpeg video slideshow script with rotate transition v4 (25.05.2019)
#
# Copyright (c) 2017-2019, Taner Sener (https://github.com/tanersener)
#
# This work is licensed under the terms of the MIT license. For a copy, see <https://opensource.org/licenses/MIT>.
#

# SCRIPT OPTIONS - CAN BE MODIFIED
WIDTH=1280
HEIGHT=720
FPS=30
TRANSITION_DURATION=1
SCREEN_MODE=4                # 1=CENTER, 2=CROP, 3=SCALE, 4=BLUR
IMAGE_DURATION=2
BACKGROUND_COLOR="black"

IFS=$'\t\n'                 # REQUIRED TO SUPPORT SPACES IN FILE NAMES

# FILE OPTIONS
# FILES=`find ../media/*.jpg | sort -r`             # USE ALL IMAGES UNDER THE media FOLDER SORTED
# FILES=('../media/1.jpg' '../media/2.jpg')         # USE ONLY THESE IMAGE FILES
FILES=`find ../media/*.jpg`                         # USE ALL IMAGES UNDER THE media FOLDER

############################
# DO NO MODIFY LINES BELOW
############################

# CALCULATE LENGTH MANUALLY
let IMAGE_COUNT=0
for IMAGE in ${FILES[@]}; do (( IMAGE_COUNT+=1 )); done

if [[ ${IMAGE_COUNT} -lt 2 ]]; then
    echo "Error: media folder should contain at least two images"
    exit 1;
fi

# INTERNAL VARIABLES
TRANSITION_FRAME_COUNT=$(( TRANSITION_DURATION*FPS ))
IMAGE_FRAME_COUNT=$(( IMAGE_DURATION*FPS ))
TOTAL_DURATION=$(( (IMAGE_DURATION+TRANSITION_DURATION)*IMAGE_COUNT))
TOTAL_FRAME_COUNT=$(( TOTAL_DURATION*FPS ))

echo -e "\nVideo Slideshow Info\n------------------------\nImage count: ${IMAGE_COUNT}\nDimension: ${WIDTH}x${HEIGHT}\nFPS: ${FPS}\nImage duration: ${IMAGE_DURATION} s\n\
Transition duration: ${TRANSITION_DURATION} s\nTotal duration: ${TOTAL_DURATION} s\n"

START_TIME=$SECONDS

# 1. START COMMAND
FULL_SCRIPT="ffmpeg -y "

# 2. ADD INPUTS
for IMAGE in ${FILES[@]}; do
    FULL_SCRIPT+="-loop 1 -i '${IMAGE}' "
done

# 3. ADD BACKGROUND COLOR SCREEN INPUT
FULL_SCRIPT+="-f lavfi -i color=${BACKGROUND_COLOR}:s=${WIDTH}x${HEIGHT},fps=${FPS} "

# 4. START FILTER COMPLEX
FULL_SCRIPT+="-filter_complex \""

# 5. PREPARE INPUTS
for (( c=0; c<${IMAGE_COUNT}; c++ ))
do
    case ${SCREEN_MODE} in
        1)
            FULL_SCRIPT+="[${c}:v]setpts=PTS-STARTPTS,scale=w='if(gte(iw/ih,${WIDTH}/${HEIGHT}),min(iw,${WIDTH}),-1)':h='if(gte(iw/ih,${WIDTH}/${HEIGHT}),-1,min(ih,${HEIGHT}))',scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=sar=1/1,fps=${FPS},format=rgba,split=2[stream$((c+1))pre1][stream$((c+1))pre2];"
        ;;
        2)
            FULL_SCRIPT+="[${c}:v]setpts=PTS-STARTPTS,scale=w='if(gte(iw/ih,${WIDTH}/${HEIGHT}),-1,${WIDTH})':h='if(gte(iw/ih,${WIDTH}/${HEIGHT}),${HEIGHT},-1)',[${IMAGE_COUNT}:v]overlay,crop=${WIDTH}:${HEIGHT},setsar=sar=1/1,fps=${FPS},format=rgba,split=2[stream$((c+1))pre1][stream$((c+1))pre2];"
        ;;
        3)
            FULL_SCRIPT+="[${c}:v]setpts=PTS-STARTPTS,scale=${WIDTH}:${HEIGHT},setsar=sar=1/1,fps=${FPS},format=rgba,split=2[stream$((c+1))pre1][stream$((c+1))pre2];"
        ;;
        4)
            FULL_SCRIPT+="[${c}:v]scale=${WIDTH}x${HEIGHT},setsar=sar=1/1,fps=${FPS},format=rgba,boxblur=100,setsar=sar=1/1[stream${c}blurred];"
            FULL_SCRIPT+="[${c}:v]scale=w='if(gte(iw/ih,${WIDTH}/${HEIGHT}),min(iw,${WIDTH}),-1)':h='if(gte(iw/ih,${WIDTH}/${HEIGHT}),-1,min(ih,${HEIGHT}))',scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=sar=1/1,fps=${FPS},format=rgba[stream${c}raw];"
            FULL_SCRIPT+="[stream${c}blurred][stream${c}raw]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2:format=rgb,setpts=PTS-STARTPTS,split=2[stream$((c+1))pre1][stream$((c+1))pre2];"
        ;;
    esac
done

# 6. APPLY PADDING
for (( c=1; c<=${IMAGE_COUNT}; c++ ))
do

    if [[ ${c} -eq ${IMAGE_COUNT} ]]; then
        SPLIT_COUNT="2"
    else
        SPLIT_COUNT="3"
    fi

    FULL_SCRIPT+="[stream${c}pre1]pad=width=${WIDTH}:height=${HEIGHT}:x=(${WIDTH}-iw)/2:y=(${HEIGHT}-ih)/2:color=#00000000,trim=duration=${TRANSITION_DURATION},select=lte(n\,${TRANSITION_FRAME_COUNT})[stream${c}out1];"

    FULL_SCRIPT+="[stream${c}pre2]pad=width=${WIDTH}:height=${HEIGHT}:x=(${WIDTH}-iw)/2:y=(${HEIGHT}-ih)/2:color=${BACKGROUND_COLOR},trim=duration=${TRANSITION_DURATION},select=lte(n\,${TRANSITION_FRAME_COUNT}),split=${SPLIT_COUNT}[stream${c}out2][stream${c}out3]"

    if [[ ${c} -eq ${IMAGE_COUNT} ]]; then
        FULL_SCRIPT+=";"
    else
        FULL_SCRIPT+="[stream${c}out4];"
    fi
done

# 7. CREATE ROTATION FRAMES
for (( c=1; c<=${IMAGE_COUNT}; c++ ))
do
    if [[ ${c} -eq 1 ]]; then
        OVERLAY_FRAME="${IMAGE_COUNT}:v"
    else
        OVERLAY_FRAME="stream$((c-1))out2"
    fi

    FULL_SCRIPT+="[stream${c}out1]rotate=2*PI*t:ow=4*${WIDTH}:c=#00000000,[${OVERLAY_FRAME}]overlay=x='${WIDTH}*3/2-w+t/${TRANSITION_DURATION}*${WIDTH}':y=0,trim=duration=${TRANSITION_DURATION},select=lte(n\,${TRANSITION_FRAME_COUNT})[stream${c}rotating];"
done

# 8. BEGIN CONCAT
for (( c=1; c<${IMAGE_COUNT}; c++ ))
do
    FULL_SCRIPT+="[stream${c}rotating][stream${c}out3][stream${c}out4]"
done

# 9. END CONCAT
FULL_SCRIPT+="[stream${IMAGE_COUNT}rotating][stream${IMAGE_COUNT}out2][stream${IMAGE_COUNT}out3]concat=n=$((3*IMAGE_COUNT)):v=1:a=0,format=yuv420p[video]\""

# 10. END
FULL_SCRIPT+=" -map [video] -vsync 2 -async 1 -rc-lookahead 0 -g 0 -profile:v main -level 42 -c:v libx264 -r ${FPS} ../transition_rotate.mp4"

eval ${FULL_SCRIPT}

ELAPSED_TIME=$(($SECONDS - $START_TIME))

echo -e '\nSlideshow created in '$ELAPSED_TIME' seconds\n'

unset $IFS