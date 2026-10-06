#!/usr/bin/env python3
"""Live per-AS stem test: stems logged by monerod (category net.dandelionpp.stems) on instances 6-9 of each vantage.
Instances 6 and 8 run with MONERO_DANDELIONPP_STEM_ASN=1 (stems drawn uniformly over the ASes of the outbound
connections), 7 and 9 with the current rule. For each instance: share of logged stems that are suspected spy nodes
(October 2026 snapshot or reachable ban-listed) in stem epochs, share of stem pairs in the same AS, and, from the polled outbound
connections, the exposure expected under each rule."""
import json, glob, csv, re, ipaddress, collections, statistics
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
spy = lambda ip: lab.get(ip) in ("flagged", "banned")
pat = re.compile(r"^(\S+ \S+).*(stem|fluff) epoch, by_asn=(\d), stems: (.*)$")
inst = {}
for f in sorted(glob.glob("data/stem/*/inst*/bitmonero.log*")):
    box, i = f.split("/")[2], int(re.search(r"inst(\d+)", f).group(1))
    k = (box, i); d = inst.setdefault(k, {"by_asn": i % 2 == 0, "maps": 0, "stems": 0, "spy": 0, "pairs": 0, "same_as": 0})
    for l in open(f, errors="replace"):
        g = pat.search(l)
        if not g: continue
        if g.group(2) != "stem": continue                     # stems are unused in fluff epochs
        ips = [x for x in g.group(4).split() if ":" not in x]
        if not ips: continue
        d["maps"] += 1; d["stems"] += len(ips); d["spy"] += sum(map(spy, ips))
        if len(ips) == 2:
            d["pairs"] += 1; d["same_as"] += asn(ips[0]) == asn(ips[1]) != 0
# expected exposure from polled outbound connections, per instance
exp = collections.defaultdict(lambda: {"cur": [], "div": []})
for f in sorted(glob.glob("data/stem/*/stem_conns.jsonl")):
    box = f.split("/")[2]
    for l in open(f):
        r = json.loads(l)
        out = [c[0] for c in r.get("c", []) if c[2] == 0 and c[0] and ":" not in c[0]]
        if not out: continue
        share = collections.defaultdict(list)
        for ip in out: share[asn(ip)].append(spy(ip))
        exp[(box, r["inst"])]["cur"].append(sum(map(spy, out)) / len(out))
        exp[(box, r["inst"])]["div"].append(statistics.mean(sum(v) / len(v) for v in share.values()))
res = {"instances": {}}
for k, d in sorted(inst.items()):
    e = exp.get(k)
    res["instances"][f"{k[0]}/{k[1]}"] = dict(d, stem_spy_pct=round(100 * d["spy"] / d["stems"], 1) if d["stems"] else None,
        expected_cur_pct=round(100 * statistics.mean(e["cur"]), 1) if e and e["cur"] else None,
        expected_div_pct=round(100 * statistics.mean(e["div"]), 1) if e and e["div"] else None)
for arm, flag in (("per_as", True), ("current", False)):
    D = [d for d in res["instances"].values() if d["by_asn"] == flag and d["stems"]]
    if not D: continue
    res[arm] = {"instances": len(D), "stem_maps": sum(d["maps"] for d in D), "stems": sum(d["stems"] for d in D),
        "stem_spy_pct_mean_of_instances": round(statistics.mean(d["stem_spy_pct"] for d in D), 1),
        "same_as_pairs_pct": round(100 * sum(d["same_as"] for d in D) / max(1, sum(d["pairs"] for d in D)), 1),
        "expected_cur_pct": round(statistics.mean(d["expected_cur_pct"] for d in D if d["expected_cur_pct"] is not None), 1),
        "expected_div_pct": round(statistics.mean(d["expected_div_pct"] for d in D if d["expected_div_pct"] is not None), 1)}
json.dump(res, open("results/stem_live.json", "w"), indent=1); print(json.dumps({k: v for k, v in res.items() if k != "instances"}, indent=1))
