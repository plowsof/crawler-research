# Responses to Rucknium's comments on asmap (2026-10-05)

**Comments:** #no-wallet-left-behind log, 2026-10-05, 16:39–16:52 UTC,
<https://libera.monerologs.net/no-wallet-left-behind/20261005>

**Paper:** *Autonomous System Deduplication for Monero Node Peer Selection*, draft v0.1. § = section, T = table,
F = figure. The method, simulation code and game are Rucknium's
([Subnet Deduplication for Monero Node Peer Selection](https://github.com/Rucknium/misc-research/blob/main/Monero-Peer-Subnet-Deduplication/pdf/monero-peer-subnet-deduplication.pdf)).
The port reproduces his 1.06 of 12 (8.8%) on his May 2025 data (§4, T13).

**Summary:** opt-in yes, default no, and AS-diverse Dandelion++ stems as the candidate default.

---

## 16:39 — opt-in

> **rucknium:** "As of now, I am not opposed to this as an opt-in flag."

**Cited:** §5.3 *Opt-in*; T2; §9 *Live measurement*; Conclusion 1.

Opt-in nodes face today's fleet, and against it asmap works:

- **Simulation:** outbound connections to suspected spy nodes fall from 4.35 to 0.13 of 12 (T2).
- **Live:** they fall from 33.8% to 2.7% (§9). 12 instances per arm on 4 machines; every default instance was worse
  than every asmap instance (exact rank test p = 3.7×10⁻⁷).

**Caveat (§5.3):** the MRL ban list is also opt-in, yet 72% of honest reachable nodes block it. At that adoption
the adversary gains enough to spread out, so for those nodes opt-in becomes the default case. Recommendation: watch
the fleet's AS count with the crawler (10 today) and advise turning the option off if it climbs towards the
hundreds.

## 16:40 — a default needs "cure not worse than the disease"

> **rucknium:** "To set it as default, you would want to have an analysis that shows, with reasonable confidence,
> that the cure would not be worse than the disease, as I did for the /24 subnet deduplication."

**Cited:** the paper's structure follows his: §4 simulation, §5 game, §5.2 adversary response, §6 feasibility;
Conclusion 2.

**Answer: the cure can be worse.**

- AS deduplication beats /24 only while the adversary can rent servers in fewer than about 370 ASes (§5.2, T7, F5).
  Over 6 seeds the break-even is 377 ± 5; at a 1.75× price ratio it is 398.
- A random-sample survey estimates 475 (330–657) rentable ASes among those already hosting Tor, Bitcoin or Monero
  servers, and about 2,700 hosting ASes worldwide (§6.3, T8).

So it is not supported as the default.

## 16:40 — the adversary could spread across ASNs

> **rucknium:** "An adversary could just spread across many ASNs, in response to a default rollout of this,
> potentially making the issue worse."

**Cited:** §5.2 *Simulated adversary response*; T6; T7 and F5; §6.1.

**Confirmed.** Spy connections out of 12 (T6):

| Adversary | /24 (master) | asmap |
|---|---|---|
| Today's bulk fleet | 4.38 | 0.13 |
| Same 1,293 nodes, one per AS | 4.71 | 8.31 |

As the number of ASes K grows, asmap falls behind (F5, T7):

| K | 9 | 99 | ~370 | 933 |
|---|---|---|---|---|
| Spy connections under asmap | 0.15 | 1.61 | 4.71 (break-even with /24) | 7.49 |

Every fleet seen so far uses few ASes: 10, 9 and 3 (§6.1). That is the adversary's best response to today's rules,
not a limit on what it could do.

## 16:41 — honest nodes concentrated in VPS ASNs

> **rucknium:** "There are many honest nodes concentrated in the ASNs of VPS vendors. An adversary could exploit
> the ASN avoidance logic to accumulate more outbound connections than the honest nodes."

**Cited:** §5, Proposition 1 and inequality (3); T1.

His threshold, carried over to ASes. Asmap beats /24 against a one-node-per-AS adversary only if
w_A / w_24 > H_24 / H_A.

- Honest nodes occupy 1,983 /24s but only 573 ASes, so the threshold is 3.46 (Oct 2026; 3.33 on May 2025 data).
- A distinct-AS node would have to cost about 3.5× a bulk node.
- Measured premium: at most 1.68× (USD 3.00–6.72 vs DigitalOcean's USD 4.00, T5).

The condition fails.

## 16:43 — ASNs have no defined size

> **rucknium:** "ASNs are harder to analyze than subnets because ASNs do not have a defined size. I used the defined
> size of subnets in my game theory analysis."

**Cited:** §2.1; Appendix A *Equivalence of the deduplicated draw*; Appendix B *Adversary nodes in groups with
honest nodes*; §5.1 *Prices*.

- **One group, one candidate.** After deduplication there is one candidate per group, so a group is drawn uniformly
  whatever its size. A large AS and a one-node AS are each one group. Appendix A proves this and checks it
  numerically against the literal shuffle-and-deduplicate draw.
- **The game needs counts, not sizes.** It uses the number of groups (H_A, m).
- **Adversary placement.** Appendix B shows the adversary does best in its own groups, not inside honest ASes.
- **Cost replaces block size.** Size matters only for the cost of occupying an AS, which §5.1 measures with prices
  instead of deriving it from a block size.

## 16:45 — his Section 4 game

> **rucknium:** "Analysis is here. See section 4 "Protocol-adversary interaction as a game" in particular"

**Cited:** §5 *Protocol-adversary interaction as a game*; Acknowledgements.

Same title, same assumptions: single-draw privacy impact, linear costs, one strategy at a time. His equations
(1)–(2) and proposition are reused, with /24 groups replaced by ASes and the strategies bulk vs AS-distinct.

## 16:47 — "Have you proved that?" (asmap makes the attack more expensive)

> **jpk68:** "At least it would ostensibly make the attack much more expensive for them"
> **rucknium:** "@jpk68:matrix.org: Have you proved that?"

**Cited:** §5.1 *Prices*, T5; §6.3 *Survey of rentable ASes*, T8; §13 *Limitations*.

**Not on price or supply:**

- **Price:** servers in other ASes cost almost the same as bulk servers (9 verified ASes at USD 3.00–6.72 per month).
  In the survey, 8 of 10 priced rentable ASes cost USD 7 or less.
- **Supply:** an estimated 475 rentable ASes within the frame, against a break-even of about 370.

**Unmeasured:** operational cost, meaning hundreds of accounts, payment methods and abuse desks (§13). That is the
only way the claim could hold.

## 16:49 — inbound stress on low-population ASNs

> **rucknium:** "If its is made the default, you would also stress nodes in low-population ASNs by creating many
> inbound connections to them."

**Cited:** §4.1 *Inbound connections*; T4 and F3 (load per node by AS size); F4 (share of inbound connections);
Conclusion 3.

**Confirmed and quantified.**

- **Each AS gets about the same share.** With asmap every AS receives about the same share of inbound connections,
  and its nodes split it.
- **Load per node (median, 90% unreachable; T4, F3):**

  | Honest nodes in the AS | 1 | 2 | 3 | 4 |
  |---|---|---|---|---|
  | asmap | 801 | 402 | 267 | 200 |
  | /24 (master) | ~150 | ~150 | ~150 | ~150 |

- **Who carries it:** 62% of ASes with honest nodes hold only one. The 764 nodes (28%) in ASes with up to 4 honest
  nodes would carry more load than today; the rest less.
- **Shares of all inbound connections (F4):** nodes alone in their AS are 13% of nodes but would get 62% of inbound
  connections, against 18% today. Nodes in ASes with 10+ honest nodes would drop from 51% to 4%.
- **Live check (§4.1, F4):** on the real network, asmap instances picked lone-AS peers 46% of the time vs 11% for
  default instances, and big-AS peers 13% vs 53% (92 and 132 honest peers, `live_peer_classes.py`). The shift is
  smaller than simulated because real peer lists over-represent large-AS nodes.
- **Spies benefit too:** a spy alone in its own AS gets the same large share. That is the AS-distinct strategy of §5.

## 16:50 — opt-in while waiting for adversary-response analysis

> **rucknium:** "Yes. I've said already that I'm ok with it as opt-in, while we wait for better analysis of how the
> adversary could respond to this."

**Cited:** §5.2, §5.3, §6, §8; Conclusions 1–2.

The adversary's response is analysed four ways:

1. **Price premium:** T6.
2. **Limited supply of ASes:** break-even over 6 seeds and price ratios up to 1.75 (T7, F5).
3. **Real peer lists:** the same response on the real peer lists of 2,527 honest nodes from four vantage points
   (§8, T12). asmap still loses against a spread adversary: 3.35 vs 2.73.
4. **Opt-in adoption:** the caveat in §5.3.

Result: opt-in yes, default no.

## 16:52 — not all defences are equally easy to circumvent

> **rucknium:** "Not all defenses are equally easy to circumvent."

**Cited:** §7 *A complementary defence: AS-diverse Dandelion++ stems*; T9–T11; F6; §8 (AS cap on peer lists);
§11 (hybrid rule); Conclusions 4–7.

The paper ranks defences by how much they lose once the adversary adapts. No rule considered beats today's against
every placement.

| Defence | vs today's fleet | Worst case after the adversary adapts |
|---|---|---|
| asmap (outbound dedup by AS) | best | unbounded loss: stem exposure up to 69.3% (F6, T9) |
| **AS-diverse stems** | stem exposure 36.5% → 12.3% (real peer lists 22.7% → 10.7%) | at most +3.3 points (+1.9 with α = 0.5; T9, T10) |
| AS cap on peer lists | 2.73 → 0.66 of 12 | loses to a spread adversary (§8, T12) |
| Hybrid /24 + per-AS limit (#7090) | 0.78 of 12 | loses to a spread adversary (§11) |

AS-diverse stems:

- **What they change:** they choose the two Dandelion++ stems uniformly over the ASes of a node's outbound
  connections. Peer selection and inbound load are unchanged, and stem load rises only moderately (T11).
- **Robustness:** no smarter placement beats them (F6, T9).
- **Status:** they are the paper's candidate default, subject to review of the Dandelion++ anonymity analysis. A
  live test of a monerod patch is running (§9, results pending).
