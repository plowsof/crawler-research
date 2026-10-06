#!/usr/bin/env python3
"""Live A/B (Section 8): outbound connections of monerod --no-sync instances with and without --asmap=embedded.
Classifies each outbound peer as suspected spy (fingerprint-flagged in the October 2026 snapshot or reachable
ban-listed) and computes, per arm, the mean share of outbound connections to suspected spy nodes, distinct ASNs,
and Dandelion++ stem exposure under the current and the AS-diverse stem rule."""
import json, glob, csv, ipaddress, collections, statistics
import json
from asmap import ASMap, net_to_prefix
import os
# replication package: peers are pseudonyms with their ASN precomputed in data/peer_asn.json
PEER_ASN = json.load(open("data/peer_asn.json")) if os.path.exists("data/peer_asn.json") else None
m = None if PEER_ASN is not None else ASMap.from_binary(open(os.environ.get("ASMAP", "data/ip_asn.dat"), "rb").read())
lab = {r["ip"]: r["label"] for r in csv.DictReader(open("data/nodes.csv"))}
for r in csv.DictReader(open("data/ban_reachable.csv")): lab[r["ip"]] = "banned"
asn_c = {}
def asn(ip):
    if PEER_ASN is not None: return PEER_ASN.get(ip, 0)
    if ip not in asn_c:
        try: asn_c[ip] = m.lookup(net_to_prefix(ipaddress.ip_network(ip + "/32"))) or 0
        except Exception: asn_c[ip] = 0
    return asn_c[ip]
rows = []
for f in sorted(glob.glob("data/ab/*.jsonl")):
    box = f.split("/")[-1][:-6]
    for l in open(f):
        r = json.loads(l)
        if "c" not in r: continue
        out = [c for c in r["c"] if c[2] == 0 and c[0] and ":" not in c[0]]
        if not out: continue
        spy = [lab.get(c[0]) in ("flagged", "banned") for c in out]
        a = [asn(c[0]) for c in out]
        share = collections.defaultdict(list)
        for s, x in zip(spy, a): share[x].append(s)
        rows.append({"box": box, "inst": r["inst"], "asmap": r["asmap"], "t": r["t"], "n": len(out),
                     "spy": sum(spy) / len(out), "asns": len(set(a)), "stem_div": statistics.mean(sum(v) / len(v) for v in share.values()),
                     "unknown": sum(c[0] not in lab for c in out) / len(out)})
res = {}
for arm in (1, 0):
    R = [r for r in rows if r["asmap"] == arm]
    if not R: continue
    res["asmap" if arm else "control"] = {"snapshots": len(R), "instances": len({(r["box"], r["inst"]) for r in R}),
        "boxes": sorted({r["box"] for r in R}), "mean_out": round(statistics.mean(r["n"] for r in R), 2),
        "spy_share_pct": round(100 * statistics.mean(r["spy"] for r in R), 2),
        "spy_of_12": round(12 * statistics.mean(r["spy"] for r in R), 2),
        "distinct_asns": round(statistics.mean(r["asns"] for r in R), 2),
        "stem_cur_pct": round(100 * statistics.mean(r["spy"] for r in R), 2),
        "stem_div_pct": round(100 * statistics.mean(r["stem_div"] for r in R), 2),
        "unknown_pct": round(100 * statistics.mean(r["unknown"] for r in R), 1),
        "per_instance_spy_pct": {f"{b}/{i}": round(100 * statistics.mean(r["spy"] for r in R if (r["box"], r["inst"]) == (b, i)), 1)
                                 for b, i in sorted({(r["box"], r["inst"]) for r in R})}}
# Outbound peers churn little under --no-sync, so the independent units are instances, not snapshots:
# distinct outbound peers per instance over the run, and an exact one-sided rank test over per-instance means
peers = collections.defaultdict(set)
for f in sorted(glob.glob("data/ab/*.jsonl")):
    box = f.split("/")[-1][:-6]
    for l in open(f):
        r = json.loads(l)
        if "c" in r: peers[(box, r["inst"])] |= {c[0] for c in r["c"] if c[2] == 0 and c[0] and ":" not in c[0]}
for arm in ("asmap", "control"):
    if arm in res:
        v = [len(peers[tuple(k.split("/")[0:1]) + (int(k.split("/")[1]),)]) for k in res[arm]["per_instance_spy_pct"]]
        res[arm]["distinct_peers_min"], res[arm]["distinct_peers_max"] = min(v), max(v)
if "asmap" in res and "control" in res:
    import itertools, math
    a = list(res["asmap"]["per_instance_spy_pct"].values()); c = list(res["control"]["per_instance_spy_pct"].values())
    u = lambda x, y: sum((xi > yi) + 0.5 * (xi == yi) for xi in x for yi in y)
    obs = u(c, a); pool = a + c; n = len(c)
    if math.comb(len(pool), n) <= 5_000_000:
        ge = sum(u([pool[i] for i in idx], [pool[j] for j in range(len(pool)) if j not in idx]) >= obs
                 for idx in map(set, itertools.combinations(range(len(pool)), n)))
        res["rank_test_p"] = ge / math.comb(len(pool), n)
    res["rank_u"] = obs; res["rank_u_max"] = len(a) * len(c)
res["hours"] = round((max(r["t"] for r in rows) - min(r["t"] for r in rows)) / 3600, 2) if rows else 0
json.dump(res, open("results/ab_live.json", "w"), indent=1); print(json.dumps(res, indent=1))
