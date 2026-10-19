#!/usr/bin/env python3
"""Published-signal hits per vantage point from probe.jsonl.gz files.
usage: hits.py <box>/probe.jsonl.gz ... > hits.json
S1 = any non-zero last_seen in the handshake peer list (stock monerod zeroes it).
S3 = full 250-entry list spanning < 10 distinct /24s (< 0.04 diversity, Kopyciok et al.).
"consistent" = hit at every vantage that got a (full, for S3) answer from that IP."""
import sys, json, gzip, os, collections

out, per = {}, collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0]))
for fn in sys.argv[1:]:
    box = os.path.basename(os.path.dirname(os.path.abspath(fn)))
    s1, s3, ans, tried = set(), set(), 0, 0
    for l in gzip.open(fn, "rt"):
        r = json.loads(l); tried += 1
        if "peers" not in r: continue
        ans += 1; ip = r["ip"]
        hit1 = any(p[3] for p in r["peers"])
        per["S1"][ip][0] += hit1; per["S1"][ip][1] += 1
        if hit1: s1.add(ip)
        if len(r["peers"]) == 250:
            hit3 = len({p[1].rsplit(".", 1)[0] for p in r["peers"] if p[0] == "ipv4"}) < 10
            per["S3"][ip][0] += hit3; per["S3"][ip][1] += 1
            if hit3: s3.add(ip)
    out[box] = {"tried": tried, "answered": ans, "S1": sorted(s1), "S3": sorted(s3)}
for k in ("S1", "S3"):
    hit = {ip: v for ip, v in per[k].items() if v[0]}
    out[k] = {"any_vantage": sorted(hit),
              "consistent": sorted(ip for ip, v in hit.items() if v[0] == v[1]),
              "hits_answers": {ip: v for ip, v in sorted(hit.items())}}
json.dump(out, sys.stdout, indent=1)
