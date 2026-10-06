#!/usr/bin/env python3
"""Every 300 s for 12 h, record outbound connections of the stem-test instances 6-9 (get_connections, JSON-RPC)."""
import json, time, urllib.request
end = time.time() + 12 * 3600
while time.time() < end:
    t = int(time.time())
    for i in (6, 7, 8, 9):
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{48190+i}/json_rpc", data=json.dumps({"jsonrpc": "2.0", "id": "0", "method": "get_connections"}).encode(), headers={"Content-Type": "application/json"})
            c = json.load(urllib.request.urlopen(req, timeout=20))["result"].get("connections", [])
            rec = {"t": t, "inst": i, "stem_asn": int(i % 2 == 0),
                   "c": [[x.get("host"), x.get("port"), int(x.get("incoming", False)), x.get("live_time")] for x in c]}
        except Exception as e:
            rec = {"t": t, "inst": i, "err": type(e).__name__}
        with open("stem_conns.jsonl", "a") as fh: fh.write(json.dumps(rec) + "\n")
    time.sleep(300)
