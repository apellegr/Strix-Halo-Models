#!/usr/bin/env python3
"""Score image Q&A on a local llama-server (started with --mmproj) against cases.json from make_vision_set.py.
A case passes when every expected group has at least one of its substrings in the answer.
usage: vision_eval.py SET_DIR PORT LABEL      e.g. vision_eval.py /tmp/vset 8010 QwenVL"""
import base64, json, sys, time, urllib.request
d, port, label = sys.argv[1:4]
cases = json.load(open(f"{d}/cases.json")); ok_n = 0; lat = []
for c in cases:
    url = "data:image/png;base64," + base64.b64encode(open(f"{d}/{c['img']}", "rb").read()).decode()
    body = {"messages": [{"role": "user", "content": [{"type": "text", "text": c["q"]}, {"type": "image_url", "image_url": {"url": url}}]}],
            "temperature": 0, "max_tokens": 800}
    t = time.time()
    try:
        r = json.load(urllib.request.urlopen(urllib.request.Request(f"http://localhost:{port}/v1/chat/completions",
            json.dumps(body).encode(), {"Content-Type": "application/json"}), timeout=300))
        a = (r["choices"][0]["message"].get("content") or "").strip()
    except Exception as e:
        a = f"ERROR {e}"
    dt = time.time() - t; lat.append(dt)
    ok = all(any(x in a.lower() for x in grp) for grp in c["expect"]); ok_n += ok
    print(f"{label:10} {c['img']:15} {'PASS' if ok else 'FAIL'} {dt:5.1f}s | {a.replace(chr(10), ' ')[:120]}", flush=True)
print(f"== {label} vision: {ok_n}/{len(cases)} | mean latency {sum(lat)/len(lat):.1f}s")
