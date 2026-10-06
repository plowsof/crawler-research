# Writes pdf/tables/numbers.tex: every number quoted in the text of the paper, as LaTeX macros,
# computed from the data and simulation results so that no number is typed by hand.
library(data.table)
source("game.R")

out <- character()
def <- function(name, value) out <<- c(out, sprintf("\\newcommand{\\%s}{%s}", name, value))
fmt <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = ",")
pct <- function(x, d = 1) fmt(100 * x, d)

d26 <- load.nodes("data/nodes.csv")
d25 <- load.nodes("data/nodes_2025.csv")

for (z in list(list(d26, "New"), list(d25, "Old"))) {
  d <- z[[1]]; s <- z[[2]]
  g <- game.inputs(d)
  def(paste0("nReach", s), fmt(nrow(d)))
  def(paste0("nHonest", s), fmt(g$h_s))
  def(paste0("nSpy", s), fmt(g$a_n))
  def(paste0("hTwentyFour", s), fmt(g$H24))
  def(paste0("hAsn", s), fmt(g$HA))
  def(paste0("hSixteen", s), fmt(d[label == "honest", uniqueN(s16)]))
  def(paste0("spyTwentyFour", s), fmt(g$a_24))
  def(paste0("spyAsn", s), fmt(g$m))
  def(paste0("threshold", s), fmt(threshold(g$H24, g$HA), 2))
  def(paste0("pObsTwentyFour", s), pct(g$p_obs_24))
  def(paste0("pObsAsn", s), pct(g$p_obs_asn, 2))
  top <- d[label != "honest", .N, by = asn][order(-N)][1]
  def(paste0("spyTopAsn", s), top$asn)
  def(paste0("spyTopAsnN", s), fmt(top$N))
  def(paste0("spyTopAsnPct", s), pct(top$N / g$a_n))
  def(paste0("honestInSpyTopAsn", s), fmt(d[label == "honest" & asn == top$asn, .N]))
  # Stackelberg with budget = observed fleet size in units of w24
  p1 <- payoffs(g$H24, g$HA, g$m, b = g$a_n, w24 = 1, wA = 1)
  def(paste0("pSS", s), pct(p1[["p_ss"]]))
  def(paste0("pAAequal", s), pct(p1[["p_aa"]]))
  def(paste0("pAS", s), pct(p1[["p_as"]], 2))
  # number of adversary-only ASNs at which ASN dedup reaches the /24-dedup bulk payoff
  def(paste0("kStar", s), fmt(ceiling(g$HA * p1[["p_ss"]] / (1 - p1[["p_ss"]]))))
}

# Simulation results
res <- list.files("results", pattern = "rds$", full.names = TRUE)
for (f in res) {
  nm <- sub("[.]rds$", "", basename(f))
  x <- readRDS(f)$nodes
  key <- gsub("[0-9_]", "", gsub("_percent_unreachable", "", nm))          # e.g. subnet / asmap / hybrid
  key <- paste0("sim", c("2026" = "New", "2025" = "Old")[substr(nm, 1, 4)],
    tools::toTitleCase(sub("subnet", "subnet", key)), ifelse(grepl("_80_", nm), "Eighty", "Ninety"))
  m <- x[malicious == FALSE, mean(n.malicious.outbound)]
  def(paste0(key, "Mean"), fmt(m, 2))
  def(paste0(key, "Pct"), pct(m / 12))
  def(paste0(key, "InMedian"), fmt(x[malicious == FALSE & reachable == TRUE, median(n.inbound)]))
  def(paste0(key, "InMax"), fmt(x[malicious == FALSE & reachable == TRUE, max(n.inbound)]))
}

cs <- jsonlite::fromJSON("results/control_set.json")
def("ctrlHosts", cs$hosts); def("ctrlIps", cs$ipv4); def("ctrlInData", cs$in_dataset)
def("ctrlFlagged", sum(unlist(cs$labels)[names(cs$labels) != "honest"]))

writeLines(out, "pdf/tables/numbers.tex")
cat(out, sep = "\n")

# Supply and prices
supply <- fread("data/prices/supply.csv")
def("nPriceAsns", nrow(supply))
def("nPriceProviders", uniqueN(supply$provider))
def("priceMin", fmt(min(supply$usd_month), 2))
def("priceMax", fmt(max(supply$usd_month), 2))
def("priceMaxRatio", fmt(max(supply$usd_month) / 4, 2))
dc <- unique(as.numeric(sub("^AS", "", regmatches(readLines("data/x4b_datacenter_ASN.txt"),
  regexpr("^AS[0-9]+", readLines("data/x4b_datacenter_ASN.txt"))))))
h <- d26[label == "honest"]
def("nDcList", fmt(length(dc)))
def("nHonestDcAsn", fmt(length(intersect(dc, unique(h$asn)))))
def("nHonestDcNodes", fmt(h[asn %in% dc, .N]))
def("nHonestNonDcAsn", fmt(uniqueN(h$asn) - length(intersect(dc, unique(h$asn)))))
sup <- unique(rbind(fread("results/supply_2026.csv"), fread("results/supply_2026_breakeven.csv")), by = c("K", "grouping"))
for (k in unique(sup$K)) for (g in c("s24", "asn", "hybrid")) {
  def(paste0("sup", c(s24 = "Subnet", asn = "Asmap", hybrid = "Hybrid")[g], "K", as.roman(k)),
    fmt(sup[K == k & grouping == g, mean], 2))
}
a <- sup[grouping == "asn"][order(K)]; base <- sup[grouping == "s24", mean[1]]
i <- which(a$mean >= base)[1]
kbe <- a$K[i - 1] + (base - a$mean[i - 1]) / (a$mean[i] - a$mean[i - 1]) * (a$K[i] - a$K[i - 1])
def("kBreakEven", fmt(round(kbe, -1)))
# Adversary response (price premium) highlights
for (ds in c("2026", "2025")) {
  r <- fread(paste0("results/response_", ds, ".csv"))
  s <- c("2026" = "New", "2025" = "Old")[[ds]]
  def(paste0("respAsmapROne", s), fmt(r[strategy == "asn_distinct_r1" & grouping == "asn", mean], 2))
  def(paste0("respSubnetObs", s), fmt(r[strategy == "observed" & grouping == "s24", mean], 2))
  def(paste0("respSubnetROne", s), fmt(r[strategy == "asn_distinct_r1" & grouping == "s24", mean], 2))
}
writeLines(out, "pdf/tables/numbers.tex")

# Inbound load of honest reachable nodes alone in their ASN (October 2026, 90 percent unreachable)
for (alg in c("subnet24", "asmap", "hybrid")) {
  fn <- paste0("results/2026_", alg, "_90_percent_unreachable.rds")
  if (!file.exists(fn)) next
  x <- merge(readRDS(fn)$nodes[reachable == TRUE & malicious == FALSE, .(ip, n.inbound)], d26[, .(ip, asn)], by = "ip")
  n <- merge(x, d26[label == "honest", .N, by = asn], by = "asn")
  key <- c(subnet24 = "Subnet", asmap = "Asmap", hybrid = "Hybrid")[[alg]]
  def(paste0("inAlone", key), fmt(n[N == 1, median(n.inbound)]))
  def(paste0("inAloneMax", key), fmt(n[N == 1, max(n.inbound)]))
  def(paste0("inBig", key), fmt(n[N >= 10, median(n.inbound)]))
  def(paste0("nAlone", key), fmt(n[N == 1, .N]))
}
writeLines(out, "pdf/tables/numbers.tex")

# Revealed supply of server ASes and ASNs seen in the Monero crawl
rs <- jsonlite::fromJSON("results/revealed_supply.json")
def("torAses", fmt(rs$tor_ipv4_ases)); def("torDc", fmt(rs$tor_dc))
def("btcAses", fmt(rs$btc_ipv4_ases)); def("btcDc", fmt(rs$btc_dc))
def("unionAses", fmt(rs$union)); def("unionDc", fmt(rs$union_dc)); def("unionDcTwo", fmt(rs$union_dc_in2plus))
def("unionUnlisted", fmt(rs$union - rs$union_dc))
ca <- jsonlite::fromJSON("results/crawl_asns.json")
def("crawlIps", fmt(ca$distinct_ipv4)); def("crawlAsns", fmt(ca$asns_all)); def("crawlAsnsDc", fmt(ca$asns_all_dc))
def("crawlReachIps", fmt(ca$reachable_ipv4)); def("crawlReachAsns", fmt(ca$asns_reachable))
def("crawlStart", format(as.POSIXct(ca$first_seen_min, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d"))
def("bitnodesTime", format(as.POSIXct(rs$bitnodes_ts, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d %H:%M"))
writeLines(out, "pdf/tables/numbers.tex")

aa <- jsonlite::fromJSON("results/adversary_asns.json")
def("banAddresses", fmt(aa$ban_addresses)); def("banAsns", fmt(aa$ban_entries_asns))
def("pegIps", fmt(aa$peg_ips_in_crawl)); def("pegAsns", fmt(aa$peg_asns_in_crawl))
writeLines(out, "pdf/tables/numbers.tex")

se <- jsonlite::fromJSON("results/survey_estimates.json")
for (k in names(se)) def(paste0("sv", gsub("[^A-Za-z]", "", tools::toTitleCase(gsub("_", " ", k))),
  c("", "Lo", "Hi")[1 + grepl("_lo$", k) + 2 * grepl("_hi$", k)]), fmt(se[[k]], ifelse(k == "tag_recall", 2, 0)))
writeLines(out, "pdf/tables/numbers.tex")

# Ban-list crawl and stem exposure
bc <- jsonlite::fromJSON("results/ban_crawl.json")
def("banProbed", fmt(bc$probed)); def("banReach", fmt(bc$reachable)); def("banReachPct", pct(bc$reachable / bc$probed))
def("banTwentyFour", fmt(bc$s24)); def("banAsnsReach", fmt(bc$asns))
def("banTopAsn", bc$top_asn[1, 1]); def("banTopAsnN", fmt(as.numeric(bc$top_asn[1, 2])))
st <- rbindlist(lapply(list.files("results", pattern = "^stem_.*csv$", full.names = TRUE), fread), fill = TRUE)
g <- function(ds, sc, gr, col, d = 1) { v <- st[dataset == ds & scenario == sc & grouping == gr][[col]]; if (length(v)) pct(v, d) else "?" }
def("stemObsCur", g(2026, "observed", "s24", "uniform.p")); def("stemObsDiv", g(2026, "observed", "s24", "diverse.p"))
def("stemObsAnyCur", g(2026, "observed", "s24", "uniform.any")); def("stemObsAnyDiv", g(2026, "observed", "s24", "diverse.any"))
def("stemWorstCur", g(2026, "asn_distinct", "s24", "uniform.p")); def("stemWorstDiv", g(2026, "asn_distinct", "s24", "diverse.p"))
def("stemWorstAsmap", g(2026, "asn_distinct", "asn", "uniform.p"))
def("stemBanCur", g(2026, "observed_ban", "s24", "uniform.p")); def("stemBanDiv", g(2026, "observed_ban", "s24", "diverse.p"))
def("stemOldCur", g(2025, "observed", "s24", "uniform.p")); def("stemOldDiv", g(2025, "observed", "s24", "diverse.p"))
def("banOutSubnet", fmt(st[dataset == 2026 & scenario == "observed_ban" & grouping == "s24", outbound.spy], 2))
def("banOutAsmap", fmt(st[dataset == 2026 & scenario == "observed_ban" & grouping == "asn", outbound.spy], 2))
writeLines(out, "pdf/tables/numbers.tex")

be <- jsonlite::fromJSON("results/breakeven.json")
def("beMean", fmt(be$seed_be_mean)); def("beSd", fmt(be$seed_be_sd)); def("beMin", fmt(be$seed_be_min)); def("beMax", fmt(be$seed_be_max))
def("beSeeds", be$n_seeds); def("beRatioMid", fmt(be$ratio_be[3])); def("beRatioHigh", fmt(be$ratio_be[4]))   # ratio_be order: 1, 1.25, 1.5, 1.75
writeLines(out, "pdf/tables/numbers.tex")
def("stemObsOut", fmt(st[dataset == 2026 & scenario == "observed" & grouping == "s24", outbound.spy], 2))
writeLines(out, "pdf/tables/numbers.tex")

# Real peer lists (B)
plr <- rbindlist(lapply(list.files("results", pattern = "^pl_.*_seed314\\.json$", full.names = TRUE), function(f) as.data.table(jsonlite::fromJSON(f))))
pv <- function(sc, r, b, cp, col, d = 2, scale = 1) fmt(scale * plr[scenario == sc & rule == r & ban == b & abs(cap - cp) < 1e-9][[col]], d)
def("plNodes", fmt(plr$nodes[1])); def("plListSpy", pv("observed", "s24", 0, 0, "list_spy_share", 1, 100))
def("plUnknown", pv("observed", "s24", 0, 0, "list_unknown_share", 1, 100))
def("plSubnetObs", pv("observed", "s24", 0, 0, "spy_out")); def("plAsmapObs", pv("observed", "asn", 0, 0, "spy_out"))
def("plCapThreeObs", pv("observed", "s24", 0, 0.031, "spy_out")); def("plCapOneObs", pv("observed", "s24", 0, 0.01, "spy_out"))
def("plSubnetSpr", pv("spread", "s24", 0, 0, "spy_out")); def("plAsmapSpr", pv("spread", "asn", 0, 0, "spy_out"))
def("plCapThreeSpr", pv("spread", "s24", 0, 0.031, "spy_out")); def("plCapOneSpr", pv("spread", "s24", 0, 0.01, "spy_out"))
def("plStemCurObs", pv("observed", "s24", 0, 0, "stem_cur", 1, 100)); def("plStemDivObs", pv("observed", "s24", 0, 0, "stem_div", 1, 100))
def("plStemCurSpr", pv("spread", "s24", 0, 0, "stem_cur", 1, 100)); def("plStemDivSpr", pv("spread", "s24", 0, 0, "stem_div", 1, 100))
def("plBanSubnetObs", pv("observed", "s24", 1, 0, "spy_out"))
def("plSubnetObsPct", pv("observed", "s24", 0, 0, "stem_cur", 1, 100))
# Stem load (C) and smarter adversaries (D)
sl <- fread("results/stemload_2026_observed_s24.csv")
def("loadMedCur", fmt(sl$cur.median, 2)); def("loadMedDiv", fmt(sl$div.median, 2)); def("loadMaxCur", fmt(sl$cur.max, 2)); def("loadMaxDiv", fmt(sl$div.max, 2))
def("loadGiniCur", fmt(sl$cur.gini, 2)); def("loadGiniDiv", fmt(sl$div.gini, 2)); def("loadAloneCur", fmt(sl$cur.alone, 2)); def("loadAloneDiv", fmt(sl$div.alone, 2))
def("stemTopTenDiv", g(2026, "top10", "s24", "diverse.p")); def("stemTopThirtyDiv", g(2026, "top30", "s24", "diverse.p")); def("stemMimicDiv", g(2026, "mimic", "s24", "diverse.p"))
writeLines(out, "pdf/tables/numbers.tex")

# Live A/B (interim)
ab <- jsonlite::fromJSON("results/ab_live.json")
def("abHours", fmt(ab$hours, 1)); def("abInst", ab$asmap$instances); def("abBoxes", length(ab$asmap$boxes))
def("abCtrlPct", fmt(ab$control$spy_share_pct, 1)); def("abAsmapPct", fmt(ab$asmap$spy_share_pct, 1))
def("abCtrlTwelve", fmt(ab$control$spy_of_12, 2)); def("abAsmapTwelve", fmt(ab$asmap$spy_of_12, 2))
def("abCtrlAsns", fmt(ab$control$distinct_asns, 1)); def("abAsmapAsns", fmt(ab$asmap$distinct_asns, 1))
def("abCtrlStemDiv", fmt(ab$control$stem_div_pct, 1))
def("abCtrlMin", fmt(min(unlist(ab$control$per_instance_spy_pct)), 0)); def("abCtrlMax", fmt(max(unlist(ab$control$per_instance_spy_pct)), 0))
def("abAsmapMax", fmt(max(unlist(ab$asmap$per_instance_spy_pct)), 0))
writeLines(out, "pdf/tables/numbers.tex")

# Stem exposure against a spreading adversary (Figure stem-spread) and live A/B independence
def("stemNineNineDiv", g(2026, "spread99", "s24", "diverse.p")); def("stemNineNineAsmap", g(2026, "spread99", "asn", "uniform.p"))
def("stemThreeSeventyAsmap", g(2026, "spread370", "asn", "uniform.p"))
def("stemObsAlpha", g(2026, "observed", "s24", "alpha50.p")); def("stemWorstAlpha", g(2026, "asn_distinct", "s24", "alpha50.p"))
def("stemRegretDiv", fmt(100 * (st[scenario == "asn_distinct" & grouping == "s24", diverse.p - uniform.p]), 1))
def("stemRegretAlpha", fmt(100 * (st[scenario == "asn_distinct" & grouping == "s24", alpha50.p - uniform.p]), 1))
def("abPeersMin", min(ab$asmap$distinct_peers_min, ab$control$distinct_peers_min))
def("abPeersMax", max(ab$asmap$distinct_peers_max, ab$control$distinct_peers_max))
def("abRankP", sprintf("%.1f\\times10^{%d}", ab$rank_test_p / 10^floor(log10(ab$rank_test_p)), floor(log10(ab$rank_test_p))))
def("abAsmapMin", fmt(min(unlist(ab$asmap$per_instance_spy_pct)), 0))
writeLines(out, "pdf/tables/numbers.tex")
def("stemObsGain", fmt(100 * (st[dataset == 2026 & scenario == "observed" & grouping == "s24", uniform.p - diverse.p]), 1))
writeLines(out, "pdf/tables/numbers.tex")
# Profile of the suspected fleet (fleet_profile.py)
fp <- jsonlite::fromJSON("results/fleet_profile.json")
def("fpDoN", fmt(fp$suspected_AS14061$nodes_with_handshake)); def("fpDoPids", fmt(fp$suspected_AS14061$distinct_peer_ids))
def("fpDoTip", fmt(fp$suspected_AS14061$within_10_blocks_of_tip_pct, 1)); def("fpHonTip", fmt(fp$honest_all$within_10_blocks_of_tip_pct, 1))
def("fpDoUnpruned", fmt(100 - fp$suspected_AS14061$pruned_pct, 1)); def("fpHonUnpruned", fmt(100 - fp$honest_all$pruned_pct, 1))
def("fpDoRpc", fmt(fp$suspected_AS14061$rpc_port_advertised_pct, 1)); def("fpHonRpc", fmt(fp$honest_all$rpc_port_advertised_pct, 1))
def("fpDoPort", fmt(fp$suspected_AS14061$default_port_pct, 0))
def("spyShareOfTopAsn", fmt(100 * d26[label != "honest" & asn == 14061, .N] / d26[asn == 14061, .N], 0))
writeLines(out, "pdf/tables/numbers.tex")
def("spySixteenNew", fmt(d26[label != "honest", uniqueN(s16)]))
writeLines(out, "pdf/tables/numbers.tex")
# Share of inbound connections by AS size (make_outputs.R, Figure inbound-share)
ish <- fread("results/inbound-share.csv")
gv <- function(sz, w) fmt(ish[size == sz & grepl(w, what) & !grepl("^Live", what), share], 0)
def("ishAloneNodes", gv("Alone in its AS", "^Honest")); def("ishAloneMaster", gv("Alone in its AS", "master")); def("ishAloneAsmap", gv("Alone in its AS", "asmap"))
def("ishBigNodes", gv("AS with 10+ honest nodes", "^Honest")); def("ishBigMaster", gv("AS with 10+ honest nodes", "master")); def("ishBigAsmap", gv("AS with 10+ honest nodes", "asmap"))
writeLines(out, "pdf/tables/numbers.tex")
ba <- jsonlite::fromJSON("results/ban_adoption.json")
def("banAdoptPct", fmt(ba$zero_banned_pct, 0)); def("banAdoptOthersPct", fmt(ba$median_banned_share_pct_others, 0))
writeLines(out, "pdf/tables/numbers.tex")
# Inbound load by number of honest nodes in the AS (Table inbound-by-asn-size, Figure inbound-by-k)
ik <- fread("results/inbound-by-asn-k.csv")
more <- ik[median.asn > median.s24]
def("ikMoreNodes", fmt(sum(more$Nodes))); def("ikMorePct", fmt(100 * sum(more$Nodes) / sum(ik$Nodes), 0))
def("ikMoreMaxK", as.character(more$group[nrow(more)])); def("ikSingleAsesPct", fmt(100 * ik[group == "1", ASes] / sum(ik$ASes), 0))
def("ikTwoAsmap", fmt(ik[group == "2", median.asn], 0)); def("ikThreeAsmap", fmt(ik[group == "3", median.asn], 0)); def("ikFourAsmap", fmt(ik[group == "4", median.asn], 0))
writeLines(out, "pdf/tables/numbers.tex")
lp <- jsonlite::fromJSON("results/live_peer_classes.json")
def("lpAloneDefault", fmt(lp$default$share_pct[["Alone in its AS"]], 0)); def("lpAloneAsmap", fmt(lp$asmap$share_pct[["Alone in its AS"]], 0))
def("lpBigDefault", fmt(lp$default$share_pct[["AS with 10+ honest nodes"]], 0)); def("lpBigAsmap", fmt(lp$asmap$share_pct[["AS with 10+ honest nodes"]], 0))
def("lpPeersDefault", lp$default$honest_peers); def("lpPeersAsmap", lp$asmap$honest_peers)
writeLines(out, "pdf/tables/numbers.tex")
