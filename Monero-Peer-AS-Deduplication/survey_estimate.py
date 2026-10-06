#!/usr/bin/env python3
"""Estimates of the number of rentable ASes from the survey sample (Section 6.3)."""
import csv, json, math
def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z*z/n; c = p + z*z/(2*n); h = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n))
    return (c - h) / d, (c + h) / d
V = list(csv.DictReader(open("data/survey/verdicts.csv"))); n = len(V)
N_frame = sum(1 for _ in open("data/survey/frame.txt"))
tags = {k: set(v) for k, v in json.load(open("data/survey/bgptools_tags.json")).items()}
R = [v for v in V if v["verdict"] == "R"]; U = [v for v in V if v["verdict"] == "U"]
priced = [v for v in R if v["usd_month"] != ""]
cheap = [v for v in priced if float(v["usd_month"]) <= 7]
cheap_v4 = [v for v in cheap if v["ipv4"] in ("included", "add-on included in price")]
tagged = [v for v in V if "vpsh" in v["bgptools_tags"]]
untagged_R = [v for v in R if "vpsh" not in v["bgptools_tags"]]
res = {"n": n, "frame": N_frame, "R": len(R), "U": len(U), "N": n - len(R) - len(U),
       "priced": len(priced), "cheap7": len(cheap), "cheap7_v4": len(cheap_v4),
       "tagged_in_sample": len(tagged), "untagged_R": len(untagged_R), "vpsh_total": len(tags["vpsh"])}
for key, k in [("R", len(R)), ("RU", len(R) + len(U)), ("cheap7", len(cheap)), ("cheap7_v4", len(cheap_v4))]:
    lo, hi = wilson(k, n)
    res[f"K_{key}"] = round(k / n * N_frame); res[f"K_{key}_lo"] = round(lo * N_frame); res[f"K_{key}_hi"] = round(hi * N_frame)
# share of rentable ASes that the bgp.tools tag misses, and the implied number of hosting ASes overall
res["tag_recall"] = round((len(R) - len(untagged_R)) / len(R), 2)
res["K_global_hosting"] = round(len(tags["vpsh"]) / res["tag_recall"])
json.dump(res, open("results/survey_estimates.json", "w"), indent=1); print(res)
