#!/usr/bin/env python3
"""Verdicts for the 100 sampled ASes (Section 6.3). Rule: R (rentable) if tagged Server Hosting by bgp.tools
or a server offer was found; N if tagged as an access network (dsl/mobile) by bgp.tools without a server offer,
or registered as a residential/education/research/media network; U otherwise. Manual evidence overrides tags."""
import csv, json
FX = {"USD": 1.0, "EUR": 1.1204, "PLN": 1.1204 / 4.3795, "RUB": 1 / 84.9309, "UAH": 1 / 45.0564}
tags = {k: set(v) for k, v in json.load(open("data/survey/bgptools_tags.json")).items()}
# manual evidence: asn -> (verdict, evidence, url, price, currency, ipv4, source)
M = {
 7489:  ("R", "KVM VPS, 512 MB, USD 35/year, 1 IPv4", "https://www.whtop.com/plans/hostus.us/155736", 35/12, "USD", "included", "secondary"),
 202053:("R", "Starter cloud server from USD 3.5/month, IPv4 included", "https://upcloud.com/pricing", 3.5, "USD", "included", "secondary"),
 58212: ("R", "self-service cloud 'Seeds' from EUR 4.07/month", "https://www.vpsbenchmarks.com/hosters/dataforest_cloud", 4.07, "EUR", "not stated", "secondary"),
 215467:("R", "VPS EUR 1.69/month, IPv4 add-on EUR 0.65/month", "https://skhron.eu/services", 1.69 + 0.65, "EUR", "add-on included in price", "primary"),
 51290: ("R", "VPS Bronze 15.00 PLN/30d net, IPv4 + IPv6", "https://hosteam.pl/pl/vps", 15.0, "PLN", "included", "primary"),
 216071:("R", "VDS/VPS from USD 2.10/month", "https://www.vdsina.com", 2.10, "USD", "not stated", "primary"),
 215590:("R", "virtual servers from 459 RUB/month", "https://xorek.cloud/", 459, "RUB", "not stated", "primary"),
 34700: ("R", "VPS 250 UAH/month, 1 IPv4 address", "https://maxnet.ua/vps/", 250, "UAH", "included", "primary"),
 40244: ("R", "VPS pro.sm.amd USD 10/month", "https://www.hivelocity.net/vps/", 10, "USD", "not stated", "primary"),
 49791: ("R", "shared vCPU server USD 1.5/month, IPv4 priced separately by region", "https://3hcloud.com/pricing", None, "", "extra, price not stated", "primary"),
 206264:("R", "VPS Medium Risk A USD 39.99/month", "https://koddos.net/medium-risk-hosting.html", 39.99, "USD", "not stated", "primary"),
 21581: ("R", "dedicated servers, bare metal, cloud instances", "https://www.m5hosting.com", None, "", "", "primary"),
 56030: ("R", "cloud servers / virtual data centre, colocation", "http://www.voyager.co.nz/business/hosting/virtual-data-centre", None, "", "", "primary"),
 42675: ("R", "dedicated servers and colocation, Stockholm", "https://websiteplanet.com/web-hosting/obehosting", None, "", "", "secondary"),
 35366: ("R", "vServer and dedicated root servers", "https://www.datacentermap.com/c/isppro-internet-kg/", None, "", "", "secondary"),
 208208:("R", "business cloud from 79 EUR/month, colocation", "https://cyberse.de/business-cloud", None, "", "", "primary"),
 200303:("R", "vServer / cloud computing", "https://lumaserv.com/managed-cloud/cloud-computing", None, "", "", "primary"),
 42532: ("R", "VPS and dedicated servers", "https://veesp.com/", None, "", "", "primary"),
 200950:("R", "VPS and dedicated servers", "https://calibour.com/services.html", None, "", "", "primary"),
 399122:("R", "VPS, cloud and dedicated servers", "https://www.vpshouse.pro/", None, "", "", "primary"),
 12310: ("R", "VPS and dedicated servers, price on request", "https://www.whtop.com/plans/ines.ro/153163", None, "", "", "secondary"),
 7296:  ("R", "bare metal servers, private cloud, colocation (sales)", "https://www.ocolo.io/colocation/dynascale-data-center/", None, "", "", "secondary"),
 198193:("N", "consumer fibre ISP", "https://www.excom.es/", None, "", "", "primary"),
 396325:("N", "residential and fibre internet", "https://fusionnetworks.me/services/residential-internet/", None, "", "", "primary"),
}
NAME_N = {36103, 30404, 10996, 54936, 1448, 61900, 137266, 9943, 24233,   # access ISPs (registry type / name)
          47610, 30983, 5408, 47, 16075}                                 # university, research network, media
rows = list(csv.DictReader(open("data/survey/sample.csv")))
out = []
for r in rows:
    a = int(r["asn"]); t = [k for k in ("vpsh", "dsl", "mobile") if a in tags[k]]
    if a in M:
        v, ev, url, price, cur, ipv4, src = M[a]
    elif "vpsh" in t:
        v, ev, url, price, cur, ipv4, src = "R", "bgp.tools tag Server Hosting", f"https://bgp.tools/as/{a}", None, "", "", "tag"
    elif t:
        v, ev, url, price, cur, ipv4, src = "N", "bgp.tools tag " + "+".join(t), f"https://bgp.tools/as/{a}", None, "", "", "tag"
    elif a in NAME_N:
        v, ev, url, price, cur, ipv4, src = "N", ("registry type " + r["pdb_type"]) if r["pdb_type"] else "network name", r["website"], None, "", "", "registry"
    else:
        v, ev, url, price, cur, ipv4, src = "U", "no offer found", r["website"], None, "", "", ""
    usd = round(price * FX[cur], 2) if price is not None else ""
    out.append({**r, "bgptools_tags": "+".join(t), "verdict": v, "evidence": ev, "evidence_url": url,
                "price": price if price is not None else "", "currency": cur, "usd_month": usd, "ipv4": ipv4, "source": src})
with open("data/survey/verdicts.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(out[0])); w.writeheader(); w.writerows(out)
import collections
c = collections.Counter(o["verdict"] for o in out); print(c)
R = [o for o in out if o["verdict"] == "R"]
cheap7 = [o for o in R if o["usd_month"] != "" and o["usd_month"] <= 7]
cheap7v4 = [o for o in cheap7 if o["ipv4"] in ("included", "add-on included in price")]
cheap14 = [o for o in R if o["usd_month"] != "" and o["usd_month"] <= 13.84]
print("R with price", sum(o["usd_month"] != "" for o in R), "<=7:", len(cheap7), "<=7 with IPv4 stated:", len(cheap7v4), "<=13.84:", len(cheap14))
for o in R: print(o["asn"], o["verdict"], o["usd_month"], o["ipv4"], o["source"], o["evidence"][:50])
