#!/usr/bin/env python3
"""Profile of the suspected spy nodes against honest reachable nodes (Section 3 box), from the handshake records of
the four-vantage crawl (data/slice_*.json) and the crawl's
enrichment records (data/enrich_all.jsonl: chain height, pruning, RPC port). Aggregates only.
Writes results/fleet_profile.json."""
import json, glob, csv, collections, statistics
lab = {r["ip"]: r["label"] for r in csv.DictReader(open("data/nodes.csv"))}
hs = {}
for f in sorted(glob.glob("data/slice_*.json")):
    for r in json.load(open(f)): hs[r[0]] = r
en = {}
for l in open("data/enrich_all.jsonl"):
    r = json.loads(l); en[r["ip"]] = r
tip = max(r["h"] for r in en.values() if r.get("h"))
out = {"tip_height": tip}
for name, sel in (("suspected_AS14061", lambda ip, a: lab[ip] != "honest" and a == "14061"),
                  ("suspected_other", lambda ip, a: lab[ip] != "honest" and a != "14061"),
                  ("honest_AS14061", lambda ip, a: lab[ip] == "honest" and a == "14061"),
                  ("honest_all", lambda ip, a: lab[ip] == "honest")):
    ips = [ip for ip in lab if ip in hs and sel(ip, str(hs[ip][5]))]
    pids = collections.Counter(hs[ip][2] for ip in ips)
    e = [en[ip] for ip in ips if ip in en and en[ip].get("h")]
    out[name] = {"nodes_with_handshake": len(ips),
        "default_port_pct": round(100 * sum(hs[ip][1] == 18080 for ip in ips) / max(1, len(ips)), 1),
        "distinct_peer_ids": len(pids), "peer_ids_shared_by_2plus_ips": sum(1 for v in pids.values() if v > 1),
        "top_version_mode": collections.Counter(hs[ip][3] for ip in ips).most_common(1)[0][0] if ips else None,
        "within_10_blocks_of_tip_pct": round(100 * sum(tip - r["h"] <= 10 for r in e) / max(1, len(e)), 1),
        "pruned_pct": round(100 * sum(bool(r.get("prune")) for r in e) / max(1, len(e)), 1),
        "rpc_port_advertised_pct": round(100 * sum(bool(r.get("rpc")) for r in e) / max(1, len(e)), 1)}
json.dump(out, open("results/fleet_profile.json", "w"), indent=1); print(json.dumps(out, indent=1))
