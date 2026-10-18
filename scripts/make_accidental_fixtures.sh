#!/bin/zsh
# Fixtures for Accidental Shots and Smart Trim. Needs ffmpeg.
# Usage: scripts/make_accidental_fixtures.sh [simulator-udid]  (adds them to the simulator when given)
set -e
cd "$(dirname "$0")/.."
A=KeeprollTests/Fixtures/Accidental; T=KeeprollTests/Fixtures/Trim
mkdir -p $A $T
F=(ffmpeg -loglevel error -y)
S=2016x1512
# Should be flagged.
$F -f lavfi -i "color=c=0x060606:s=${S},noise=alls=3:allf=t" -frames:v 1 $A/accidental-pocket.jpg
$F -f lavfi -i "color=c=0x8a8580:s=${S},noise=alls=1:allf=t" -frames:v 1 $A/accidental-blank.jpg
$F -f lavfi -i "testsrc2=s=${S},hue=s=0" -f lavfi -i "color=c=0xd2785a:s=900x1512" \
   -filter_complex "[1]gblur=sigma=40[f];[0][f]overlay=0:0" -frames:v 1 $A/accidental-finger.jpg
# Must NOT be flagged.
$F -f lavfi -i "color=c=0x080a12:s=${S}" -vf "geq=r='if(lt(hypot(X-1500,Y-400),90),245,8)':g='if(lt(hypot(X-1500,Y-400),90),245,10)':b='if(lt(hypot(X-1500,Y-400),90),235,18)'" -frames:v 1 $A/control-night-moon.jpg
$F -f lavfi -i "gradients=s=${S}:c0=0x5a8ce6:c1=0xbcd8f5:x0=0:y0=0:x1=0:y1=1512:nb_colors=2" -frames:v 1 $A/control-clear-sky.jpg
# Videos. The pocket tail is noisy dark, like a real sensor in a pocket: pure black
# compresses to nothing, so trimming it would save almost no space.
$F -f lavfi -i "testsrc2=s=640x360:d=12:r=30" -f lavfi -i "color=c=0x0a0908:s=640x360:d=30:r=30,noise=alls=10:allf=t" \
   -filter_complex "[0][1]concat=n=2:v=1[v]" -map "[v]" -c:v libx264 -crf 25 -pix_fmt yuv420p $T/trim-pocket-tail.mp4
# Control: a pure-black tail frees almost nothing, so it must NOT be offered.
$F -f lavfi -i "testsrc2=s=640x360:d=12:r=30" -f lavfi -i "color=c=black:s=640x360:d=30:r=30" \
   -filter_complex "[0][1]concat=n=2:v=1[v]" -map "[v]" -c:v libx264 -crf 28 -pix_fmt yuv420p $T/control-black-tail.mp4
$F -f lavfi -i "color=c=0x050505:s=640x360:d=20:r=30,noise=alls=2:allf=t" -c:v libx264 -crf 28 -pix_fmt yuv420p $T/trim-all-dark.mp4
$F -f lavfi -i "testsrc2=s=640x360:d=13:r=30" -f lavfi -i "color=c=black:s=640x360:d=4:r=30" -f lavfi -i "testsrc2=s=640x360:d=13:r=30" \
   -filter_complex "[0][1][2]concat=n=3:v=1[v]" -map "[v]" -c:v libx264 -crf 28 -pix_fmt yuv420p $T/control-short-dark-moment.mp4
echo "Fixtures written to $A and $T"
if [ -n "$1" ]; then
  xcrun simctl addmedia "$1" $A/*.jpg $T/*.mp4
  echo "Added to simulator $1"
fi
