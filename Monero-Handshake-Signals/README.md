# Handshake signals from Kopyciok et al. (active probing)

Re-implementation of two peer-list signals from Kopyciok, Schmid & Victor,
[*Friend or Foe? Identifying Anomalous Peers in Monero's P2P Network*](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.AFT.2026.31)
(AFT 2026, [arXiv](https://arxiv.org/abs/2509.10214), [their code](https://github.com/ykpyck/monero-traffic-analysis)).
Instead of a passive node capture, this does one handshake to every target and reads the peer list it returns,
so a single machine is enough and no monerod is needed. Daily counts are on the
[Monero P2P Observatory](https://observer.monerodevs.org) ("Published spy-node signals").

| Signal | Rule | Why it is anomalous |
|---|---|---|
| S1 `last_seen` | `last_seen` present in the handshake peer list, any value (including 0) | stock monerod zeroes it before sending (`net_node.inl`) and `KV_SERIALIZE_OPT` omits zero, so it never appears |
| S3 diversity | a full 250-entry list spanning < 10 distinct /24s | stock monerod samples its white list; a list this concentrated is not one |

## Files

| File | What it does |
|---|---|
| `levin.py` | minimal Levin / portable-storage client (handshake, ping) |
| `ffprobe.py` | one handshake per target, writes JSONL with the full peer list; binds source ports 41000-48999 |
| `ruckcap.py` | `ffprobe.py` run that also logs each attempt's (source port, ip, port) |
| `ruckcap.sh` | full-payload `tcpdump` + `ruckcap.py` + `pcapcut.py`, one vantage point |
| `pcapcut.py` | cuts a capture down to the probe's own flows |
| `pcap2probe.py` | rebuilds `probe.jsonl` from a capture (reassembles and decodes each handshake response) |
| `hits.py` | S1 / S3 hits per vantage point, plus the IPs every vantage agrees on |

## Run

Python 3 only (standard library); `ruckcap.sh` also needs `tcpdump` and sudo.

### Check a capture you were sent

A capture bundle has `pcapng/<vantage>/<vantage>.pcapng`, `probe/<vantage>/probe.jsonl.gz` and these scripts.

```
mkdir capture && tar -xJf monero-handshake-capture-YYYYMMDD.tar.xz -C capture && cd capture

# 1. hits from the parsed probe data
python3 scripts/hits.py probe/*/probe.jsonl.gz > my_hits.json
python3 -c "import json; s=json.load(open('my_hits.json'))['S1']; print(len(s['any_vantage']), 'IPs send last_seen;', len(s['consistent']), 'on every answer')"

# 2. same, but rebuild the probe data from the pcaps first (no trust in the parsed files)
for b in pcapng/*/; do b=$(basename $b); python3 scripts/pcap2probe.py pcapng/$b/$b.pcapng probe/$b/probe.jsonl && gzip -f probe/$b/probe.jsonl; done
python3 scripts/hits.py probe/*/probe.jsonl.gz > my_hits.json
```

`my_hits.json`: per vantage `S1` / `S3` lists, plus `S1` and `S3` across vantages (`any_vantage`, `consistent` = hit on
every answer that IP gave, `hits_answers` = [hits, answers] per IP).

### Make your own capture

Targets are `ip port` lines, e.g. from `get_peer_list` on your own node or any crawl.

```
./ruckcap.sh <name> [workers]        # writes <name>.pcap.gz, probe.jsonl.gz
python3 hits.py */probe.jsonl.gz > hits.json
```

Without a capture: `python3 ffprobe.py targets.txt probe.jsonl 48`.

The pcaps contain only the probe's handshakes, so the signals in the paper that need held or inbound connections
(throttled timed sync, ping flooding, short-lived connections) do not apply to them. To read them with the
authors' tool, lay them out as `data/pcapng/<name>/<name>.pcapng` (pcap files: `editcap -F pcapng` first).
As of its commit 0bec011 the tool needs a patch to see `last_seen` (it does not extract int64 values) and to run
without LaTeX: see [issue #1](https://github.com/ykpyck/monero-traffic-analysis/issues/1).
