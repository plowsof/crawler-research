# Tables and figures for the paper. Style follows Rucknium's subnet-deduplication-plots-and-simulations.R.
library(data.table)
library(ggplot2)
library(treemapify)
library(gt)
source("game.R")

fix.latex.table <- function(latex.output, label) {
  latex.output <- gsub("caption*", "caption", latex.output, fixed = TRUE)
  latex.output <- gsub("\\large ", "", latex.output, fixed = TRUE)
  latex.output <- gsub("\\end{table}",
    paste0("\\label{table-", label, "}\n\\end{table}"), latex.output, fixed = TRUE)
  cat(latex.output, file = paste0("pdf/tables/", label, ".tex"))
  invisible(NULL)
}


scenario.label <- function(nm) {
  paste0(ifelse(substr(nm, 1, 4) == "2026", "Oct 2026", "May 2025"), ", ",
    ifelse(grepl("asmap", nm), "AS dedup", ifelse(grepl("hybrid", nm), "hybrid", "/24 dedup")), ", ",
    ifelse(grepl("_80_", nm), "80", "90"), "% unreachable")
}
d26 <- load.nodes("data/nodes.csv")
d25 <- load.nodes("data/nodes_2025.csv")

# ---- Concentration table ----
conc <- function(d, dataset) {
  d[, .(Dataset = dataset,
    Nodes = ifelse(label[1] == "honest", "Honest", "Suspected spy"),
    `IP addresses` = .N, `/16 subnets` = uniqueN(s16), `/24 subnets` = uniqueN(s24),
    ASNs = uniqueN(asn),
    `Effective ASNs` = round(1 / sum((table(asn) / .N)^2), 1)), by = .(lab = label != "honest")][, lab := NULL][]
}
concentration <- rbind(conc(d26, "Oct 2026"), conc(d25, "May 2025"))
latex.output <- gt(concentration) |>
  tab_header(title = "Grouping of reachable nodes by /16 subnet, /24 subnet, and autonomous system") |>
  fmt_number(columns = 3:6, decimals = 0) |>
  tab_options(table.font.size = "") |> as_latex() |> as.character()
fix.latex.table(latex.output, "concentration")
fwrite(concentration, "results/concentration.csv")

# ---- Treemaps (Oct 2026 data) ----
d26[, type := ifelse(label == "honest", "honest", "spy")]
d26[, y := 1]
d26[, asn.label := paste0("AS", asn)]

png("pdf/images/treemap-asn.png", width = 1000, height = 1000)
print(ggplot(d26, aes(area = y, fill = type, subgroup = asn.label, subgroup2 = s24)) +
  labs(title = "ASN treemap of honest and suspected spy nodes",
    subtitle = "Black perimeters indicate autonomous systems. Yellow indicates /24 subnets.") +
  geom_treemap() +
  geom_treemap_subgroup2_border(colour = "yellow", size = 1.5) +
  geom_treemap_subgroup_border(color = "black", size = 2) +
  scale_fill_manual(name = "Node type:",
    values = c(scales::muted("blue", l = 40), scales::muted("red", l = 60))) +
  geom_treemap_subgroup_text(colour = "white", place = "centre", grow = TRUE, min.size = 8) +
  theme(plot.title = element_text(size = 25), plot.subtitle = element_text(size = 18),
    legend.title = element_text(size = 18), legend.text = element_text(size = 18),
    legend.position = "top"))
dev.off()

dedup.treemap <- function(by, title, file) {
  x <- d26[, .(spy.share = mean(type == "spy")), by = by]
  x[, y := 1]
  setorder(x, spy.share)
  png(file, width = 1000, height = 1000)
  print(ggplot(x, aes(area = y, fill = spy.share)) +
    labs(title = title) +
    geom_treemap(start = "topright") +
    scale_fill_gradient2(name = "Spy share:    ", midpoint = 0.5,
      low = scales::muted("blue", l = 40), high = scales::muted("red", l = 60), limits = c(0, 1)) +
    guides(fill = guide_colorbar(barwidth = 20)) +
    theme(plot.title = element_text(size = 25), legend.title = element_text(size = 18),
      legend.text = element_text(size = 18), legend.position = "top"))
  dev.off()
}
dedup.treemap("s24", "Treemap after /24 subnet deduplication (monero master)", "pdf/images/treemap-24-dedup.png")
dedup.treemap("asn", "Treemap after ASN deduplication (--asmap)", "pdf/images/treemap-asn-dedup.png")

# ---- Simulation tables ----
scen <- data.table(file = list.files("results", pattern = "rds$", full.names = TRUE))
scen[, name := sub("[.]rds$", "", basename(file))]
order.names <- as.vector(outer(c("subnet24", "asmap", "hybrid"), c("2026_%s_80", "2026_%s_90", "2025_%s_80", "2025_%s_90"),
  function(alg, pat) paste0(sprintf(pat, alg), "_percent_unreachable")))
order.names <- order.names[order(rep(1:4, each = 3))]
scen <- scen[match(order.names, name)][!is.na(file)]
nets <- setNames(lapply(scen$file, readRDS), scen$name)

malicious.connection.summary <- sapply(nets, function(x) {
  x$nodes[malicious == FALSE, c(`N honest nodes` = .N, summary(n.malicious.outbound))]
}) |> t() |> data.frame(check.names = FALSE)
malicious.connection.summary <- cbind(Scenario = scenario.label(rownames(malicious.connection.summary)),
  malicious.connection.summary)
fwrite(malicious.connection.summary, "results/malicious-connection-summary.csv")
latex.output <- gt(malicious.connection.summary) |>
  tab_header(title = "Summary statistics: Number of outbound connections, out of 12, to suspected spy nodes") |>
  fmt_number(drop_trailing_zeros = TRUE) |>
  tab_options(table.font.size = "") |> as_latex() |> as.character()
fix.latex.table(latex.output, "malicious-connection-summary")

inbound.summary <- sapply(nets, function(x) {
  x$nodes[malicious == FALSE & reachable == TRUE, c(`N honest reachable nodes` = .N, summary(n.inbound))]
}) |> t() |> data.frame(check.names = FALSE)
inbound.summary <- cbind(Scenario = scenario.label(rownames(inbound.summary)), inbound.summary)
fwrite(inbound.summary, "results/inbound-summary.csv")
latex.output <- gt(inbound.summary) |>
  tab_header(title = "Summary statistics: Number of inbound connections to honest reachable nodes") |>
  fmt_number(drop_trailing_zeros = TRUE) |>
  tab_options(table.font.size = "") |> as_latex() |> as.character()
fix.latex.table(latex.output, "inbound-summary")

if (all(sapply(nets, function(x) !is.null(x$network.stats)))) {
  network.stats.summary <- sapply(nets, function(x) sapply(x$network.stats, function(s) s$centralization)) |>
    t() |> data.frame(check.names = FALSE)
  network.stats.summary <- cbind(Scenario = scenario.label(rownames(network.stats.summary)), network.stats.summary)
  setDT(network.stats.summary)
  setnames(network.stats.summary, c("centr_betw", "centr_clo", "centr_degree", "centr_eigen"),
    c("Betweenness", "Closeness", "Degree", "Eigenvector"))
  fwrite(network.stats.summary, "results/network-stats.csv")
  latex.output <- gt(network.stats.summary) |>
    tab_header(title = "Centrality statistics of the network") |>
    fmt_scientific() |>
    tab_options(latex.use_longtable = TRUE, table.font.size = "") |> as_latex() |> as.character()
  fix.latex.table(latex.output, "network-stats")
}

# Inbound connections of honest reachable nodes by the number of honest reachable nodes in their AS
# (October 2026, 90 percent unreachable): number of ASes and nodes in each size class, median inbound
# connections per node, and the class's share of all inbound connections, with /24 and AS deduplication
k.class <- function(k) factor(fcase(k == 1, "1", k == 2, "2", k == 3, "3", k == 4, "4", k <= 9, "5-9",
  k <= 49, "10-49", k <= 199, "50-199", default = "200+"), c("1", "2", "3", "4", "5-9", "10-49", "50-199", "200+"))
asn.k <- d26[label == "honest", .(k = .N), by = asn]
by.k <- function(alg) {
  x <- merge(nets[[paste0("2026_", alg, "_90_percent_unreachable")]]$nodes[reachable == TRUE & malicious == FALSE,
    .(ip, n = as.numeric(n.inbound))], d26[, .(ip, asn)], by = "ip")
  x <- merge(x, asn.k, by = "asn")
  x[, .(median = median(n), share = 100 * sum(n) / x[, sum(n)]), by = .(group = k.class(k))]
}
inbound.k <- merge(merge(asn.k[, .(ASes = .N, Nodes = sum(k)), by = .(group = k.class(k))], by.k("subnet24"), by = "group"),
  by.k("asmap"), by = "group", suffixes = c(".s24", ".asn"))[order(group)]
inbound.k[, nodes.pct := 100 * Nodes / sum(Nodes)]
fwrite(inbound.k, "results/inbound-by-asn-k.csv")
tab <- inbound.k[, .(`Honest nodes in AS` = as.character(group), ASes, `Nodes (pct)` = sprintf("%d (%.0f)", Nodes, nodes.pct),
  `/24: median` = median.s24, `AS: median` = median.asn,
  `/24: share (pct)` = round(share.s24, 1), `AS: share (pct)` = round(share.asn, 1))]
latex.output <- gt(tab) |>
  tab_header(title = "Inbound connections of honest reachable nodes by the number of honest reachable nodes in their AS",
    subtitle = "October 2026, 90 percent unreachable. Median: inbound connections per node. Share: percent of all inbound connections of honest reachable nodes") |>
  fmt_number(columns = c(`/24: median`, `AS: median`), drop_trailing_zeros = TRUE) |>
  tab_options(table.font.size = "") |> as_latex() |> as.character()
fix.latex.table(latex.output, "inbound-by-asn-size")
kl <- melt(inbound.k[, .(group, `/24 deduplication (master)` = median.s24, `AS deduplication (--asmap)` = median.asn)],
  id.vars = "group", variable.name = "Rule", value.name = "median")
png("pdf/images/inbound-by-k.png", width = 1000, height = 560)
print(ggplot(kl, aes(group, median, fill = Rule)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.8) +
  geom_text(aes(label = round(median)), position = position_dodge(width = 0.85), vjust = -0.4, size = 5) +
  scale_fill_manual(values = c("#4c4c4c", "#00aebf"), name = "") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
  labs(title = "Inbound connections per honest node, by how many honest nodes share its AS (Oct 2026 data)",
    subtitle = paste0("Median per node, 90 percent unreachable. With AS deduplication a node gets about ", round(inbound.k[group == "1", median.asn]), " divided by the number of honest nodes in its AS"),
    x = "Honest reachable nodes in the node's AS", y = "Median inbound connections per node") +
  theme(legend.position = "top", plot.title = element_text(size = 18), plot.subtitle = element_text(size = 13),
    legend.text = element_text(size = 14), axis.text = element_text(size = 15), axis.title = element_text(size = 15)))
dev.off()

# Who receives the inbound connections: share of honest reachable nodes and share of all their inbound connections,
# by the number of honest reachable nodes in the node's AS (October 2026, 90 percent unreachable; the shares are the
# same with 80 percent)
asn.size <- d26[label == "honest", .(asn.n = .N), by = asn]
size.class <- function(n) factor(fcase(n == 1, "Alone in its AS", n <= 9, "AS with 2-9 honest nodes",
  default = "AS with 10+ honest nodes"), c("Alone in its AS", "AS with 2-9 honest nodes", "AS with 10+ honest nodes"))
inshare <- rbindlist(lapply(c(subnet24 = "Inbound connections, /24 dedup (master)", asmap = "Inbound connections, AS dedup (--asmap)"), function(lbl) {
  alg <- if (grepl("master", lbl)) "subnet24" else "asmap"
  x <- merge(nets[[paste0("2026_", alg, "_90_percent_unreachable")]]$nodes[malicious == FALSE & reachable == TRUE,
    .(ip, n.inbound = as.numeric(n.inbound))], d26[, .(ip, asn)], by = "ip")
  x <- merge(x, asn.size, by = "asn")[, size := size.class(asn.n)]
  x[, .(share = 100 * sum(n.inbound) / x[, sum(n.inbound)], nodes = .N, nodes.share = 100 * .N / nrow(x)), by = size][, what := lbl]
}))
inshare <- rbind(unique(inshare[, .(size, share = nodes.share, what = "Honest reachable nodes")]), inshare[, .(size, share, what)])
# live check: honest outbound peers of the live A/B instances by the same classes (live_peer_classes.py)
lp <- jsonlite::fromJSON("results/live_peer_classes.json")
inshare <- rbind(inshare,
  data.table(size = factor(names(lp$default$share_pct), levels(inshare$size)), share = unlist(lp$default$share_pct), what = "Live peers, default"),
  data.table(size = factor(names(lp$asmap$share_pct), levels(inshare$size)), share = unlist(lp$asmap$share_pct), what = "Live peers, --asmap"))
inshare[, what := factor(what, c("Honest reachable nodes", "Inbound connections, /24 dedup (master)", "Inbound connections, AS dedup (--asmap)",
  "Live peers, default", "Live peers, --asmap"))]
fwrite(inshare, "results/inbound-share.csv")
png("pdf/images/inbound-share.png", width = 1000, height = 680)
print(ggplot(inshare, aes(share, size, fill = what)) +
  geom_col(position = position_dodge2(reverse = TRUE), width = 0.8) +
  geom_text(aes(label = paste0(round(share), "%")), position = position_dodge2(width = 0.8, reverse = TRUE), hjust = -0.15, size = 5.5) +
  scale_fill_manual(values = c("#bdbdbd", "#4c4c4c", "#00aebf", "#9e9e9e", "#7fd6df"), name = "") +
  guides(fill = guide_legend(nrow = 2)) +
  scale_x_continuous(limits = c(0, 75), expand = c(0, 0)) + scale_y_discrete(limits = rev) +
  labs(title = "Who receives the inbound connections (October 2026 data)",
    subtitle = "Honest nodes grouped by how many honest reachable nodes share their AS; simulation and live A/B peers",
    x = "Percent", y = NULL) +
  theme(legend.position = "top", plot.title = element_text(size = 19), plot.subtitle = element_text(size = 14),
    legend.text = element_text(size = 14), axis.text = element_text(size = 15), axis.title = element_text(size = 15)))
dev.off()

# ---- Game: adversary share as a function of the ASN price premium ----
ratios <- exp(seq(log(1), log(100), length.out = 400))
curves <- rbindlist(lapply(list(list(d26, "Oct 2026 data"), list(d25, "May 2025 data")), function(z) {
  g <- game.inputs(z[[1]])
  b <- g$a_n  # budget = size of the observed fleet, in units of w24
  rbindlist(lapply(ratios, function(r) {
    p <- payoffs(g$H24, g$HA, g$m, b = b, w24 = 1, wA = r)
    s <- stackelberg(p)
    data.table(dataset = z[[2]], ratio = r, algorithm = c("/24 deduplication", "ASN deduplication"),
      p = c(s[["subnet24"]], s[["asmap"]]), threshold = threshold(g$H24, g$HA))
  }))
}))
png("pdf/images/price-premium.png", width = 1000, height = 600)
print(ggplot(curves, aes(ratio, 100 * p, colour = algorithm)) +
  geom_line(linewidth = 1.3) +
  geom_vline(aes(xintercept = threshold), linetype = "dashed") +
  facet_wrap(vars(dataset)) +
  scale_x_log10() +
  scale_colour_manual(values = c("#4c4c4c", "#00aebf"), name = "") +
  labs(title = "Adversary's best-response share of an honest node's draws",
    subtitle = "Dashed line: H24 / HA. Budget fixed at the size of the observed suspected spy fleet.",
    x = "Price premium of an ASN-distinct node, wA / w24 (log scale)", y = "Percent") +
  theme(legend.position = "top", plot.title = element_text(size = 20), plot.subtitle = element_text(size = 14),
    legend.text = element_text(size = 15), axis.text = element_text(size = 14),
    axis.title = element_text(size = 15), strip.text = element_text(size = 15)))
dev.off()
fwrite(curves, "results/price-premium-curves.csv")

# ---- Adversary response table ----
resp <- rbindlist(lapply(list.files("results", pattern = "^response_.*csv$", full.names = TRUE), fread))
if (nrow(resp)) {
  resp[, Data := ifelse(dataset == 2026, "Oct 2026", "May 2025")]
  resp[, Adversary := ifelse(strategy == "observed", "Observed suspected spy nodes",
    paste0("AS-distinct, wA/w24 = ", sub("asn_distinct_r", "", strategy)))]
  resp[, Rule := c(s24 = "/24 dedup", asn = "AS dedup", hybrid = "Hybrid")[grouping]]
  resp[, ratio := suppressWarnings(as.numeric(sub("asn_distinct_r", "", strategy)))]
  wide <- dcast(resp, Data + ratio + Adversary + n.adversary ~ Rule, value.var = "mean")
  setorder(wide, -Data, ratio, na.last = FALSE)
  wide[, ratio := NULL]
  setcolorder(wide, c("Data", "Adversary", "n.adversary", "/24 dedup", "AS dedup", "Hybrid"))
  setnames(wide, "n.adversary", "Adversary nodes")
  fwrite(wide, "results/response-table.csv")
  latex.output <- gt(wide) |>
    tab_header(title = "Mean outbound connections, out of 12, to adversary nodes when the adversary responds") |>
    fmt_number(columns = c("/24 dedup", "AS dedup", "Hybrid"), decimals = 2) |>
    tab_options(table.font.size = "") |> as_latex() |> as.character()
  fix.latex.table(latex.output, "response")
}

# ---- Verified VPS prices (supply) ----
supply <- fread("data/prices/supply.csv")
honest.per.asn <- d26[label == "honest", .N, by = asn]
supply <- merge(supply, honest.per.asn, by = "asn", all.x = TRUE)
supply[is.na(N), N := 0]
setorder(supply, usd_month, provider)
price.table <- supply[, .(Provider = provider, ASN = paste0("AS", asn), Plan = sub(" *\\(.*", "", plan),
  `List price` = paste(formatC(price, format = "f", digits = 2), currency),
  `USD/month` = usd_month, `Honest nodes in ASN` = N)]
latex.output <- gt(price.table) |>
  tab_header(title = "Cheapest plan with a public IPv4 address, by hosting provider",
    subtitle = "Prices from the providers' pricing pages, accessed 2026-10-05. EUR converted at the ECB reference rate of 2026-10-05 (1.1204 USD/EUR)") |>
  fmt_number(columns = "USD/month", decimals = 2) |>
  tab_options(table.font.size = "") |> as_latex() |> as.character()
fix.latex.table(latex.output, "prices")

# ---- Supply-constrained response ----
sup <- rbind(fread("results/supply_2026.csv"), fread("results/supply_2026_breakeven.csv"))
sup <- unique(sup, by = c("K", "grouping"))
sup[, Rule := factor(c(s24 = "/24 deduplication (master)", asn = "AS deduplication (--asmap)",
  hybrid = "Hybrid")[grouping], c("/24 deduplication (master)", "AS deduplication (--asmap)", "Hybrid"))]
fwrite(sup, "results/supply-all.csv")
png("pdf/images/supply.png", width = 1000, height = 600)
print(ggplot(sup, aes(K, mean, colour = Rule)) +
  geom_line(linewidth = 1.3) + geom_point(size = 3) +
  scale_colour_manual(values = c("#4c4c4c", "#00aebf", "#f26822"), name = "") +
  labs(title = "Adversary spreads the observed fleet over K rentable ASNs (October 2026 data)",
    subtitle = "1,293 adversary nodes, each in its own /24, split evenly over K datacenter ASNs",
    x = "Number of ASNs the adversary rents servers in (K)",
    y = "Mean outbound connections to adversary, of 12") +
  theme(legend.position = "top", plot.title = element_text(size = 19), plot.subtitle = element_text(size = 14),
    legend.text = element_text(size = 14), axis.text = element_text(size = 14), axis.title = element_text(size = 15)))
dev.off()
sup.table <- dcast(sup, K ~ Rule, value.var = "mean")
latex.output <- gt(sup.table) |>
  tab_header(title = "Mean outbound connections, out of 12, to adversary nodes spread over K ASNs") |>
  fmt_number(columns = -1, decimals = 2) |>
  tab_options(table.font.size = "") |> as_latex() |> as.character()
fix.latex.table(latex.output, "supply")

# ---- Rentable-AS survey ----
sv <- fread("data/survey/verdicts.csv", colClasses = list(character = c("usd_month", "price")))
sv[, name := ifelse(pdb_name != "", pdb_name, as_name)]
sv[, name := substr(gsub("[_&%#$]", " ", name), 1, 26)]
sv[, ipv4s := fcase(ipv4 == "included", "incl.", ipv4 == "add-on included in price", "add-on", ipv4 == "not stated", "n/s",
  grepl("extra", ipv4), "extra", default = "")]
sv[, src := fcase(source == "primary", "P", source == "secondary", "S", source == "tag", "T", default = "")]
rent <- sv[verdict == "R", .(ASN = paste0("AS", asn), Network = name, Evidence = substr(gsub("[_&%#$]", " ", evidence), 1, 42),
  `USD/mo` = usd_month, IPv4 = ipv4s, Src = src)]
rent[, usd.num := as.numeric(`USD/mo`)]; setorder(rent, usd.num, na.last = TRUE); rent[, usd.num := NULL]
latex.output <- gt(rent) |>
  tab_header(title = "Sampled ASes classified as rentable",
    subtitle = "IPv4: incl. = included, add-on = priced add-on included in the price, n/s = not stated. Src: P = provider page, S = third-party listing, T = bgp.tools tag only") |>
  tab_options(table.font.size = "small") |> as_latex() |> as.character()
fix.latex.table(latex.output, "survey-rentable")
full <- sv[, .(ASN = paste0("AS", asn), Network = name, Seen = sources, `bgp.tools` = bgptools_tags, Verdict = verdict)]
latex.output <- gt(full) |>
  tab_header(title = "All sampled ASes and their classification") |>
  tab_options(latex.use_longtable = TRUE, table.font.size = "footnotesize") |> as_latex() |> as.character()
fix.latex.table(latex.output, "survey-full")

# ---- Dandelion++ stem exposure ----
st <- rbindlist(lapply(list.files("results", pattern = "^stem_.*csv$", full.names = TRUE), fread), fill = TRUE)
lab <- c(observed = "Observed", observed_ban = "Observed + ban-list nodes",
  spread99 = "Spread, 99 ASes", spread370 = "Spread, 370 ASes", spread933 = "Spread, 933 ASes",
  asn_distinct = "One node per AS", top10 = "10 largest honest ASes",
  top30 = "30 largest honest ASes", mimic = "Honest AS distribution")
st[, Adversary := lab[scenario]]
st[, Data := ifelse(dataset == 2026, "Oct 2026", "May 2025")]
st <- st[order(-dataset, match(scenario, names(lab)), grouping)]
stem.table <- st[, .(Data, Adversary, Outbound = ifelse(grouping == "s24", "/24", "AS"),
  `Spy/12` = outbound.spy, `Stem cur.` = 100 * uniform.p, `Stem AS-div.` = 100 * diverse.p)]
fwrite(stem.table, "results/stem-table.csv")
latex.output <- gt(stem.table) |>
  tab_header(title = "Dandelion++ stem exposure: percent probability that a stem is an adversary node",
    subtitle = "Stem: current = 2 stems uniformly from the outbound connections (src/net/dandelionpp.cpp). AS-diverse = stems drawn uniformly over the ASes of the outbound connections") |>
  fmt_number(columns = 4:6, decimals = 1) |>
  tab_options(table.font.size = "small") |> as_latex() |> as.character()
fix.latex.table(latex.output, "stem")
alpha <- st[grouping == "s24" & dataset == 2026 & scenario %in% c("observed", "asn_distinct") & !is.na(alpha50.p),
  .(scenario, `0` = uniform.p, `0.25` = alpha25.p, `0.5` = alpha50.p, `0.75` = alpha75.p, `1` = diverse.p)]
alpha <- melt(alpha, id.vars = "scenario", variable.name = "alpha", value.name = "p")
alpha <- dcast(alpha, alpha ~ scenario, value.var = "p")
setnames(alpha, c("alpha", "asn_distinct", "observed"), c("Weight exponent alpha", "One node per AS", "Observed suspected spy nodes"))
alpha[, (2:3) := lapply(.SD, function(x) 100 * x), .SDcols = 2:3]
latex.output <- gt(alpha) |>
  tab_header(title = "Stem exposure (percent) with connections weighted by n^(-alpha), /24 deduplication, October 2026") |>
  fmt_number(columns = 2:3, decimals = 1) |>
  tab_options(table.font.size = "small") |> as_latex() |> as.character()
fix.latex.table(latex.output, "stem-alpha")

# ---- Real peer lists (B) ----
pl <- rbindlist(lapply(list.files("results", pattern = "^pl_.*_seed314\\.json$", full.names = TRUE), function(f) as.data.table(jsonlite::fromJSON(f))))
pl[, Strategy := paste0(ifelse(rule == "s24", "/24", "AS"), ifelse(cap > 0, sprintf(" + cap %.1f%%", 100 * cap), ""))]
pl[, Adversary := ifelse(scenario == "observed", "Observed", "Spread")]
pl[, `Ban list` := ifelse(ban == 1, "on", "off")]
setorder(pl, scenario, ban, rule, cap)
pl.table <- pl[, .(Adversary, Ban = `Ban list`, Strategy, `List spy %` = 100 * list_spy_share, `Spy/12` = spy_out,
  `Stem cur. %` = 100 * stem_cur, `Stem AS-div. %` = 100 * stem_div)]
fwrite(pl.table, "results/pl-table.csv")
latex.output <- gt(pl.table) |>
  tab_header(title = "Outbound selection from real peer lists",
    subtitle = "Each honest reachable node selects from the white-list entries it returned in four handshakes. Spread: the same entries, one AS per adversary node. Cap: per-AS cap on list entries") |>
  fmt_number(columns = 4:7, decimals = 1) |> fmt_number(columns = 5, decimals = 2) |>
  tab_options(table.font.size = "small") |> as_latex() |> as.character()
fix.latex.table(latex.output, "peerlists")

# ---- Stem load (C) ----
sl <- rbindlist(lapply(list.files("results", pattern = "^stemload_2026_.*_s24\\.csv$", full.names = TRUE), fread))
sl <- sl[scenario %in% c("observed", "asn_distinct", "observed_ban")]
sl[, Adversary := c(observed = "Observed suspected spy nodes", observed_ban = "Observed + reachable ban-list nodes",
  asn_distinct = "One node per AS")[scenario]]
sl[, Adversary := c(observed = "Observed", observed_ban = "Observed + ban-list", asn_distinct = "One node per AS")[scenario]]
sl.table <- sl[, .(Adversary, `Med. cur.` = cur.median, `Med. div.` = div.median, `Max cur.` = cur.max,
  `Max div.` = div.max, `Gini cur.` = cur.gini, `Gini div.` = div.gini, `Alone cur.` = cur.alone, `Alone div.` = div.alone)]
latex.output <- gt(sl.table) |>
  tab_header(title = "Expected stem traffic received per honest reachable node, /24 deduplication, October 2026",
    subtitle = "Sum over originators of the probability that the node is chosen as a stem. cur. = current rule, div. = AS-diverse. Alone: only honest reachable node in its AS") |>
  fmt_number(columns = 2:9, decimals = 2) |>
  tab_options(table.font.size = "small") |> as_latex() |> as.character()
fix.latex.table(latex.output, "stemload")

# ---- Stem exposure as the adversary spreads over more ASes ----
spy.asns <- d26[label != "honest", uniqueN(asn)]; n.spy <- d26[label != "honest", .N]
st <- rbindlist(lapply(c(observed = spy.asns, spread99 = 99, spread370 = 370, spread933 = 933, asn_distinct = n.spy),
  function(k) data.table(K = k)), idcol = "scenario")
fmt.n <- function(x) formatC(x, format = "d", big.mark = ",")
st <- merge(st, rbindlist(lapply(st$scenario, function(s) fread(paste0("results/stem_2026_", s, ".csv")))), by = "scenario")
stl <- rbind(
  st[grouping == "s24", .(K, Rule = "/24 dedup, current stems (master)", p = uniform.p)],
  st[grouping == "s24", .(K, Rule = "/24 dedup, alpha = 0.5 stems", p = alpha50.p)],
  st[grouping == "s24", .(K, Rule = "/24 dedup, per-AS stems", p = diverse.p)],
  st[grouping == "asn", .(K, Rule = "AS dedup (--asmap)", p = uniform.p)])
stl[, Rule := factor(Rule, unique(Rule))]
png("pdf/images/stem-spread.png", width = 1000, height = 600)
print(ggplot(stl, aes(K, 100 * p, colour = Rule)) +
  geom_line(linewidth = 1.3) + geom_point(size = 3) +
  scale_x_log10(breaks = sort(unique(stl$K))) +
  scale_colour_manual(values = c("#4c4c4c", "#9a6a12", "#f26822", "#00aebf"), name = "") +
  guides(colour = guide_legend(nrow = 2)) +
  labs(title = "Stem exposure as the adversary spreads over more ASes (October 2026 data)",
    subtitle = paste0("Leftmost point: observed suspected spy nodes (", spy.asns, " ASes); others: ", fmt.n(n.spy),
      " nodes spread evenly over K ASes; rightmost: one node per AS"),
    x = "Number of ASes the adversary's nodes are in (log scale)",
    y = "Probability a stem is an adversary node (%)") +
  theme(legend.position = "top", plot.title = element_text(size = 19), plot.subtitle = element_text(size = 13),
    legend.text = element_text(size = 14), axis.text = element_text(size = 14), axis.title = element_text(size = 15)))
dev.off()
