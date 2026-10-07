#!/bin/zsh
# rec.sh NAME SECONDS PRE args... : launch Nyx with args, wait PRE seconds, record SECONDS of screen to clips/NAME.mov
S=5BB44DBD-DBE4-4FA3-84C8-8E92D3B3F0B3
name=$1; secs=$2; pre=$3; shift 3
dir=${NYX_CLIPS:-/tmp/nyx-promo/clips}
mkdir -p $dir; rm -f $dir/$name.mov
xcrun simctl terminate $S com.harrypakhale.nyx 2>/dev/null
xcrun simctl io $S recordVideo --codec=h264 --force $dir/$name.mov >/dev/null 2>&1 &
rp=$!
sleep 1.0
xcrun simctl launch $S com.harrypakhale.nyx "$@" >/dev/null
sleep $(( pre + secs ))
kill -INT $rp; wait $rp 2>/dev/null
echo "$name done"
