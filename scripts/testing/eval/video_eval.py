#!/usr/bin/env python3
"""Score video Q&A on a local llama-server (started with --mmproj and access to ffmpeg, e.g. --video-ffmpeg-dir)
against cases.json from make_video_set.py. A case passes when every expected group has one of its substrings
in the answer and no "reject" substring appears.
usage: video_eval.py SET_DIR PORT LABEL      e.g. video_eval.py /tmp/videoset 8001 Qwen3.8"""
import base64, json, sys, time, urllib.request
d, port, label = sys.argv[1:4]
cases = json.load(open(f"{d}/cases.json")); ok_n = 0; lat = []
for c in cases:
    url = "data:video/mp4;base64," + base64.b64encode(open(f"{d}/{c['video']}", "rb").read()).decode()
    body = {"messages": [{"role": "user", "content": [{"type": "text", "text": c["q"]}, {"type": "video_url", "video_url": {"url": url}}]}],
            "temperature": 0, "max_tokens": 1500}
    t = time.time()
    try:
        r = json.load(urllib.request.urlopen(urllib.request.Request(f"http://localhost:{port}/v1/chat/completions",
            json.dumps(body).encode(), {"Content-Type": "application/json"}), timeout=600))
        a = (r["choices"][0]["message"].get("content") or "").strip(); pt = r.get("usage", {}).get("prompt_tokens", 0)
    except urllib.error.HTTPError as e:
        a, pt = f"ERROR {e.code} {e.read()[:200]!r}", 0
    except Exception as e:
        a, pt = f"ERROR {e}", 0
    dt = time.time() - t; lat.append(dt); low = a.lower()
    ok = all(any(x in low for x in g) for g in c["expect"]) and not any(x in low for x in c.get("reject", []))
    ok_n += ok
    print(f"{label:10} {c['video']:14} {'PASS' if ok else 'FAIL'} {dt:5.1f}s {pt:5d} prompt tok | {a.replace(chr(10), ' ')[:130]}", flush=True)
print(f"== {label} video: {ok_n}/{len(cases)} | mean latency {sum(lat)/len(lat):.1f}s")
