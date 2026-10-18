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
# A finger right against the lens is completely out of focus: a soft-edged warm blob.
$F -f lavfi -i "testsrc2=s=${S},hue=s=0" -f lavfi -i "color=c=0xd2785a:s=${S},format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='clip(255*(1100-X)/400,0,255)'" \
   -filter_complex "[0][1]overlay=0:0" -frames:v 1 $A/accidental-finger.jpg
# Must NOT be flagged.
$F -f lavfi -i "color=c=0x080a12:s=${S}" -vf "geq=r='if(lt(hypot(X-1500,Y-400),90),245,8)':g='if(lt(hypot(X-1500,Y-400),90),245,10)':b='if(lt(hypot(X-1500,Y-400),90),235,18)'" -frames:v 1 $A/control-night-moon.jpg
# A portrait with an orange top: warm along one edge, but its edge is in focus.
$F -f lavfi -i "testsrc2=s=1512x2016,hue=s=0" -f lavfi -i "color=c=0xe0662a:s=1512x700" -f lavfi -i "color=c=0xc58c6a:s=500x600" \
   -filter_complex "[0][1]overlay=0:1316[a];[a][2]overlay=506:600" -frames:v 1 $A/control-portrait-orange-top.jpg
# A starfield: dark, with small scattered stars.
$F -f lavfi -i "color=c=0x05060a:s=${S}" -vf "geq=lum='if(eq(mod(floor(X/48)*31+floor(Y/48)*17,13),0)*lt(hypot(mod(X,48)-24,mod(Y,48)-24),5),240,14)':cb=128:cr=128" -frames:v 1 $A/control-starfield.jpg
# A plain colour swatch: deliberate, not blank.
$F -f lavfi -i "color=c=0x2878c8:s=${S}" -frames:v 1 $A/control-colour-swatch.jpg
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
# Control: dark for 30 s but someone is talking (a tone stands in for speech): never cut.
$F -f lavfi -i "testsrc2=s=640x360:d=12:r=30" -f lavfi -i "color=c=0x0a0908:s=640x360:d=30:r=30,noise=alls=10:allf=t" \
   -f lavfi -i "anullsrc=r=44100:cl=mono:d=12" -f lavfi -i "sine=f=300:r=44100:d=30,volume=0.4" \
   -filter_complex "[0][1]concat=n=2:v=1[v];[2][3]concat=n=2:v=0:a=1[a]" -map "[v]" -map "[a]" \
   -c:v libx264 -crf 25 -pix_fmt yuv420p -c:a aac $T/control-dark-with-sound.mp4
echo "Fixtures written to $A and $T"
if [ -n "$1" ]; then
  xcrun simctl addmedia "$1" $A/*.jpg $T/*.mp4
  echo "Added to simulator $1"
fi
