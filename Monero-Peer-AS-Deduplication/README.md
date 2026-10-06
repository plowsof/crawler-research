# Replication package: Autonomous System Deduplication for Monero Node Peer Selection

Code and data for every number, table and figure in the research note. The simulation, the game-theoretic
model and the May 2025 data are Rucknium's ([Subnet Deduplication for Monero Node Peer Selection](https://github.com/Rucknium/misc-research/blob/main/Monero-Peer-Subnet-Deduplication/pdf/monero-peer-subnet-deduplication.pdf),
[xmrpeers](https://github.com/Rucknium/xmrpeers)); this package applies them to AS deduplication. His original scripts are not copied here: see
[`R/peer-selection.R` in xmrpeers](https://github.com/Rucknium/xmrpeers/blob/main/R/peer-selection.R) and
[`Monero-Peer-Subnet-Deduplication/` in misc-research](https://github.com/Rucknium/misc-research/tree/main/Monero-Peer-Subnet-Deduplication).
`pdf/mrl.cls` is the Monero Research Lab LaTeX class used by Rucknium's notes.

`rucknium-concerns.md` answers each of Rucknium's comments of 2026-10-05 with citations to this note.

## What is in it

| Directory | Contents |
|---|---|
| `*.R`, `*.py` | All analysis code (see the map below) |
| `data/` | Public inputs and the pseudonymised October 2026 data |
| `results/` | Outputs of the long simulation runs (aggregates only), so that `numbers.R` and `make_outputs.R` can be run without re-simulating |
| `live/` | Scripts and the monerod patch for the live measurements |
| `pdf/` | LaTeX source, built PDF, generated tables and figures |

## Three levels of reproducibility

1. **Public data, fully reproducible.** The May 2025 data (`data/nodes_2025.csv`, built from `good_peers` and
   `ban_list_v1` in xmrpeers), the MRL ban list, the hosting-price pages and the rentable-AS survey (saved pages
   in `data/prices/` and `data/survey/`), Tor relays (Onionoo), Bitcoin nodes (Bitnodes), the X4BNet datacenter
   list, iptoasn.com AS names and the embedded asmap (`data/ip_asn.dat`, sha256 `03580ade...afc12`, as in
   monero pull request #11474).
2. **October 2026 data, pseudonymised.** `data/nodes.csv`, `data/ban_reachable.csv`, `data/peerlists/`,
   `data/ab/` and `data/stem/` come from the four-vantage crawl of the Monero P2P Observatory
   (https://observer.monerodevs.org) and from the live runs. Every IPv4 address is replaced by a keyed hash
   (HMAC-SHA256, key not published). /24 and /16 subnets are replaced by labels that keep their original sort
   order, because R's `split()` orders groups, and with them the random draws, by label. ASNs and labels are
   unchanged, and ban-list membership and peer ASNs are precomputed (`banned_ids.txt`, `asn_of.json`,
   `s24_of.json`, `peer_asn.json`). The scripts detect these files and run unchanged.
3. **Not released.** Raw crawl records with IP addresses, and the suspected-spy fingerprint classifier. The
   fingerprints are withheld so that the fleet operators cannot evade them. Both are available to the Monero
   Research Lab on request. `fleet_profile.py` is included but needs the raw handshake records; its aggregate
   output is in `results/fleet_profile.json`.

## Verified

With the pseudonymised data, these reproduce the paper's results exactly, digit for digit:

- `stem_sim.R 2026 observed` and `stem_sim.R 2026 observed_ban`;
- `pl_sim.py` for the observed and spread scenarios, /24 and AS rules, with and without the ban list;
- `ab_analyze.py`, including the per-instance shares and the exact rank test.

The other R simulations use the same data and `sim.R` code path.

## Map from the paper to the code

Run from this directory. R needs `data.table`, `ggplot2`, `treemapify`, `gt`, `jsonlite`; Python 3 needs only
the standard library (`asmap.py` is Bitcoin Core's asmap decoder, MIT).

| Paper | Command | Output |
|---|---|---|
| Sections 4–5, Tables 2–5, Figures 1–4 (network simulation, inbound) | `Rscript run_sims.R` | `results/{2026,2025}_{subnet24,asmap,hybrid}_{80,90}_percent_unreachable.rds` |
| Section 5 (game) | `game.R` (sourced by `numbers.R`) | macros |
| Price premium (response) | `Rscript response_sim.R 2026`, `Rscript response_sim.R 2025` | `results/response_*.csv` |
| Limited supply, break-even, Figure supply | `Rscript supply_sim.R`, `Rscript supply_sim.R 99 200 300 370 400 600 933`, then seeds/ratios with `SEED=<n> RATIO=<r> Rscript supply_sim.R ...` and `Rscript breakeven.R` | `results/supply_2026*.csv`, `results/breakeven.json` |
| Section 5.3 (opt-in, ban-list adoption) | `python3 ban_adoption.py` | `results/ban_adoption.json` |
| Section 6 (where servers run, survey) | `survey_sample.py`, `survey_fetch.py`, `survey_deep.py`, `survey_verdicts.py`, `survey_estimate.py` | `data/survey/`, `results/survey_estimates.json` |
| Section 7 (Dandelion++ stems), Figure stem-spread | `Rscript stem_sim.R 2026 <scenario>` for `observed observed_ban spread99 spread370 spread933 asn_distinct top10 top30 mimic`, and `2025 observed` | `results/stem_*.csv`, `results/stemload_*.csv` |
| Section 8 (real peer lists) | `[BAN=1] [CAP=0.031] python3 pl_sim.py <observed|spread> <s24|asn> x` | `results/pl_*.json` |
| Section 4.1 (live check of inbound concentration) | `python3 live_peer_classes.py` | `results/live_peer_classes.json` |
| Section 9 (live A/B) | `python3 ab_analyze.py` | `results/ab_live.json` |
| Section 9 (live AS-diverse stems) | `python3 stem_analyze.py` | `results/stem_live.json` |
| All numbers in the text | `Rscript numbers.R` | `pdf/tables/numbers.tex` |
| All tables and figures | `Rscript make_outputs.R` | `pdf/tables/*.tex`, `pdf/images/*.png` |
| PDF | `cd pdf && pdflatex monero-peer-asn-deduplication && bibtex monero-peer-asn-deduplication && pdflatex ... && pdflatex ...` | |

## Live measurements (`live/`)

- `ab_start_any.sh`, `ab_poll.py`: 6 `monerod --no-sync --out-peers 12 --in-peers 0` instances per machine,
  even-numbered with `--asmap=embedded`, built from monero pull request #11474 (`-DARCH=default`); outbound
  connections polled every 5 minutes for 24 hours. Run on four machines in AS16276 (OVH, two machines),
  AS24940 (Hetzner) and AS31898 (Oracle Cloud).
- `stem.patch`, `stem_start.sh`, `stem_poll.py`: experimental AS-diverse Dandelion++ stems on top of #11474.
  With `MONERO_DANDELIONPP_STEM_ASN=1`, the stem candidates are reduced to one random outbound connection per
  AS (embedded asmap, /24 for unmapped addresses), so the two stems are drawn uniformly over ASes. Stems are
  logged under the category `net.dandelionpp.stems` (`--log-level 0,net.dandelionpp.stems:INFO`). Not proposed
  for merging as is: it is an environment switch for measurement.
