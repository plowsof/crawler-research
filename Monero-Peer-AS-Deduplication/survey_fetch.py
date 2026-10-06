#!/usr/bin/env python3
"""Fetch each sampled AS's website and scan for rentable-server offers. Saves pages under data/survey/pages."""
import csv, re, html, subprocess, json, concurrent.futures as cf
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"
KW = re.compile(r"\b(VPS|VDS|virtual (private )?servers?|cloud servers?|cloud (compute|instances?|VPS)|dedicated servers?|bare[- ]metal|server hosting|root ?server|KVM)\b", re.I)
PRICE = re.compile(r"(?:[$€£]\s?\d{1,3}(?:[.,]\d{1,2})?|\d{1,3}(?:[.,]\d{1,2})?\s?(?:€|EUR|USD|zł|PLN|руб|₽|kr))\s*(?:/|per|a|par|pro)?\s*(?:mo|month|monat|mois|mes|мес)", re.I)
def text(h):
    h = re.sub(r"(?s)<script.*?</script>|<style.*?</style>", " ", h)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", h)))
def fetch(url, path):
    r = subprocess.run(["curl", "-sL", "-m", "25", "-A", UA, "-o", path, "-w", "%{http_code} %{url_effective}", url], capture_output=True, text=True)
    return r.stdout
def job(row):
    a, site = row["asn"], row["website"].strip()
    out = {"asn": a, "website": site, "status": "", "kw": [], "price": [], "links": []}
    if not site: return out
    if not site.startswith("http"): site = "http://" + site
    p = f"data/survey/pages/AS{a}.html"
    out["status"] = fetch(site, p)
    try: h = open(p, errors="ignore").read()
    except FileNotFoundError: return out
    t = text(h)
    out["kw"] = sorted({m.group(0).lower() for m in KW.finditer(t)})[:8]
    out["price"] = [t[max(0, m.start()-60):m.end()+10] for m in PRICE.finditer(t)][:3]
    out["links"] = sorted({l for l in re.findall(r'href="([^"]+)"', h) if KW.search(l) or re.search(r"(vps|vds|cloud|server|dedic|hosting|pricing|tarif|preise)", l, re.I)})[:8]
    return out
rows = list(csv.DictReader(open("data/survey/sample.csv")))
with cf.ThreadPoolExecutor(8) as ex: res = list(ex.map(job, rows))
json.dump(res, open("data/survey/fetch.json", "w"), indent=1)
for r in res:
    print(r["asn"], r["status"][:60], "| KW:", ",".join(r["kw"])[:80], "| PRICE:", (r["price"][0] if r["price"] else "")[:70])
