# Handshake signals from Kopyciok et al. (active probing)

Re-implementation of two peer-list signals from Kopyciok, Schmid & Victor,
[*Friend or Foe? Identifying Anomalous Peers in Monero's P2P Network*](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.AFT.2026.31)
(AFT 2026, [arXiv](https://arxiv.org/abs/2509.10214), [their code](https://github.com/ykpyck/monero-traffic-analysis)).
Instead of a passive node capture, this does one handshake to every target and reads the peer list it returns,
so a single machine is enough and no monerod is needed. Daily counts are on the
[Monero P2P Observatory](https://observer.monerodevs.org) ("Published spy-node signals").

| Signal | Rule | Why it is anomalous |
|---|---|---|
| S1 `last_seen` | any non-zero `last_seen` in the handshake peer list | stock monerod zeroes it before sending (`net_node.inl`) and zero values are not serialised |
| S3 diversity | a full 250-entry list spanning < 10 distinct /24s | stock monerod samples its white list; a list this concentrated is not one |

## Files

| File | What it does |
|---|---|
| `levin.py` | minimal Levin / portable-storage client (handshake, ping) |
| `ffprobe.py` | one handshake per target, writes JSONL with the full peer list; binds source ports 41000-48999 |
| `ruckcap.py` | `ffprobe.py` run that also logs each attempt's (source port, ip, port) |
| `ruckcap.sh` | full-payload `tcpdump` + `ruckcap.py` + `pcapcut.py`, one vantage point |
| `pcapcut.py` | cuts a capture down to the probe's own flows |
| `hits.py` | S1 / S3 hits per vantage point, plus the IPs every vantage agrees on |

## Run

Targets are `ip port` lines, e.g. from `get_peer_list` on your own node or any crawl.

```
./ruckcap.sh <name> [workers]        # needs tcpdump (sudo) and python3; writes <name>.pcap.gz, probe.jsonl.gz
python3 hits.py */probe.jsonl.gz > hits.json
```

Without a capture: `python3 ffprobe.py targets.txt probe.jsonl 48`.

The pcaps contain only the probe's handshakes, so the signals in the paper that need held or inbound connections
(throttled timed sync, ping flooding, short-lived connections) do not apply to them. To read them with the
authors' tool, convert with `editcap -F pcapng` and lay them out as `data/pcapng/<name>/`.
