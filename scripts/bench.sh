#!/bin/bash
# Measures on THIS machine and writes JSON to docs/bench-results.json. READMEs quote only these numbers.
# Usage: scripts/bench.sh [soak_seconds]   (default 1800 = the 30-minute soak; use 600 for the 10-minute session)
set -e
cd "$(dirname "$0")/.."
SOAK=${1:-1800}
scripts/build.sh release >/dev/null 2>&1
APP=build/Chitter.app/Contents/MacOS/Chitter
OUT=docs/bench-results.json
python3 - "$OUT" <<'PY'
import json,sys; json.dump({"date":__import__("datetime").date.today().isoformat()},open(sys.argv[1],"w"))
PY
run() { perl -e 'alarm 600; exec @ARGV' "$@" 2>/dev/null | tail -1; }
APPLE=$(run $APP --transcribe Resources/Fixtures/en.wav --lang en-US)
WHISPER=$(run $APP --transcribe Resources/Fixtures/en.wav --lang en --whisper)
START=$(python3 - <<'PY'
import subprocess,time,os
env=dict(os.environ,CHITTER_BENCH_EXIT="1")
t=[]
for _ in range(5):
    s=time.time(); subprocess.run(["build/Chitter.app/Contents/MacOS/Chitter"],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); t.append(time.time()-s)
t.sort(); print(t[len(t)//2])
PY
)
SIZE=$(du -sk build/Chitter.app | cut -f1)
SOAKJSON=$($APP --soak "$SOAK" Resources/Fixtures/en.wav 2>docs/soak.log | tail -1)
python3 - "$OUT" "$APPLE" "$WHISPER" "$START" "$SIZE" "$SOAKJSON" <<'PY'
import json,sys,statistics
out,apple,whisper,start,size,soak=sys.argv[1:]
r={"apple":json.loads(apple) if apple else None,"whisper":json.loads(whisper) if whisper else None,
   "cold_start_median_s":float(start),"app_size_mb":int(size)/1024}
s=json.loads(soak) if soak else None
if s:
    tl=s["timeline"]; secs=s["seconds"]
    r["soak"]={"engine":s["engine"],"seconds":secs,"finals":s["finals"],
      "avg_cpu_pct":statistics.mean(x[2] for x in tl) if tl else None,"peak_rss_mb":max(x[1] for x in tl) if tl else None}
    # memory growth: mean RSS of the first-vs-last quarter after a 60 s warm-up
    w=[x for x in tl if x[0]>60]
    if len(w)>=8:
        q=len(w)//4; a=statistics.mean(x[1] for x in w[:q]); b=statistics.mean(x[1] for x in w[-q:])
        r["soak"]["rss_growth_pct"]=(b-a)/a*100
for k in ("apple","whisper"):
    d=r[k]
    if d: d["real_time_factor"]=d["wall_seconds"]/d["audio_seconds"]
json.dump(r,open(out,"w"),indent=2); print(json.dumps(r,indent=2))
PY
