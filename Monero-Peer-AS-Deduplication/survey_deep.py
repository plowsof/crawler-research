#!/usr/bin/env python3
"""Second pass for uncertain ASes: multilingual keyword scan of the home page and of up to 3 linked
server/hosting pages. Pages saved as data/survey/pages/AS<asn>_<k>.html."""
import json, re, html, subprocess, sys, urllib.parse, concurrent.futures as cf
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"
KW = re.compile(r"(VPS|VDS|virtual (private )?server|cloud server|dedicated server|bare[- ]metal|root ?server|server mieten|vserver|serwer(y)? (vps|dedykowan)|виртуальн\w* сервер|выделенн\w* сервер|аренда сервер|serveur (dédié|virtuel)|servidor(es)? (dedicado|virtual)|colocation|colo\b|IaaS|instance)", re.I)
PRICE = re.compile(r"(?:[$€£]\s?\d{1,4}(?:[.,]\d{1,2})?|\d{1,4}(?:[.,]\d{1,2})?\s?(?:€|EUR|USD|zł|PLN|руб\.?|₽|kr|CHF|lei|грн))\s*(?:/|per|a|par|pro|в)?\s*(?:mo\b|month|monat|mois|mes|мес|miesi)", re.I)
def text(h):
    h = re.sub(r"(?s)<script.*?</script>|<style.*?</style>", " ", h)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", h)))
def get(url, path):
    subprocess.run(["curl", "-sL", "-m", "25", "-A", UA, "-o", path, url], capture_output=True)
    try: return open(path, errors="ignore").read()
    except FileNotFoundError: return ""
def job(a, site):
    out = {"asn": a, "hits": [], "prices": [], "pages": []}
    base = site if site.startswith("http") else "http://" + site
    h = get(base, f"data/survey/pages/AS{a}_0.html")
    links = []
    for l in re.findall(r'href="([^"#]+)"', h):
        if re.search(r"(vps|vds|cloud|server|dedic|hosting|colo|pricing|tarif|preise|cennik|uslugi|services)", l, re.I):
            u = urllib.parse.urljoin(base, l)
            if urllib.parse.urlparse(u).netloc.split(":")[0].endswith(urllib.parse.urlparse(base).netloc.split(":")[0].replace("www.", "")) and u not in links:
                links.append(u)
    pages = [(base, h)]
    for k, u in enumerate(links[:3], 1):
        pages.append((u, get(u, f"data/survey/pages/AS{a}_{k}.html")))
    for u, hh in pages:
        t = text(hh)
        hs = sorted({m.group(0).lower() for m in KW.finditer(t)})
        ps = [t[max(0, m.start()-70):m.end()+5] for m in PRICE.finditer(t)][:2]
        if hs or ps: out["pages"].append({"url": u, "kw": hs[:6], "price": ps})
    return out
sites = json.loads(sys.stdin.read())
with cf.ThreadPoolExecutor(8) as ex:
    res = list(ex.map(lambda x: job(*x), sites.items()))
json.dump(res, open("data/survey/deep.json", "w"), indent=1)
for r in res:
    print("== AS" + r["asn"])
    for p in r["pages"][:3]: print("   ", p["url"][:70], "|", ",".join(p["kw"])[:70], "|", (p["price"][0] if p["price"] else "")[:80])
