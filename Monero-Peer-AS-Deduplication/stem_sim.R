# Dandelion++ stem exposure under the current stem rule and an ASN-diverse stem rule.
# Current rule (src/net/dandelionpp.cpp, connection_map): each epoch a node picks CRYPTONOTE_DANDELIONPP_STEMS = 2
# stems uniformly at random, without replacement, from its outbound connections.
# ASN-diverse rule (proposal): pick 2 distinct ASNs uniformly from the ASNs of the outbound connections, then one
# connection uniformly within each ASN (if only one ASN, both stems come from it).
# Outbound connections are simulated with gen.network.grouped() (honest reachable originators only).
# Usage: Rscript stem_sim.R <dataset 2026|2025> <scenario> ; writes results/stem_<dataset>_<scenario>.csv
library(data.table)
source("sim.R")
setDTthreads(1)

args <- commandArgs(trailingOnly = TRUE)
dataset <- args[1]; scenario <- args[2]
nodes <- fread(c("2026" = "data/nodes.csv", "2025" = "data/nodes_2025.csv")[[dataset]],
  colClasses = list(character = c("s16", "s24")))
honest <- nodes[label == "honest"]
fleet <- nodes[label != "honest", .N]

synthetic <- function(asns) {
  n <- length(asns)
  data.table(ip = paste0("synthetic-", seq_len(n)), s16 = paste0("syn16-", seq_len(n)),
    s24 = paste0("syn24-", seq_len(n)), asn = asns, label = "spy", own = 0)
}
dc <- unique(as.numeric(sub("^AS", "", regmatches(readLines("data/x4b_datacenter_ASN.txt"),
  regexpr("^AS[0-9]+", readLines("data/x4b_datacenter_ASN.txt"))))))
k99 <- intersect(dc, unique(honest$asn))
set.seed(1); others <- sample(setdiff(dc, k99))

d <- switch(scenario,
  observed = nodes,
  # observed fleet plus the reachable ban-listed nodes (a node that does not use the ban list)
  observed_ban = rbind(nodes, fread("data/ban_reachable.csv", colClasses = list(character = c("s16", "s24"))), fill = TRUE),
  spread99 = rbind(honest, synthetic(rep_len(k99, fleet)), fill = TRUE),
  spread370 = rbind(honest, synthetic(rep_len(c(k99, others)[1:370], fleet)), fill = TRUE),
  spread933 = rbind(honest, synthetic(rep_len(dc, fleet)), fill = TRUE),
  asn_distinct = rbind(honest, synthetic(4200000000 + seq_len(fleet)), fill = TRUE),
  # smarter adversary against AS-diverse stems: concentrate the fleet in the ASes that host the most honest nodes
  top10 = rbind(honest, synthetic(rep_len(honest[, .N, by = asn][order(-N)]$asn[1:10], fleet)), fill = TRUE),
  top30 = rbind(honest, synthetic(rep_len(honest[, .N, by = asn][order(-N)]$asn[1:30], fleet)), fill = TRUE),
  # proportional to honest presence: mimic the honest AS distribution exactly
  mimic = rbind(honest, synthetic(sample(honest$asn, fleet, replace = TRUE)), fill = TRUE),
  stop("unknown scenario"))
d[, asn := as.numeric(asn)]

stem.exposure <- function(conn.spy, conn.asn) {
  # conn.spy: logical vector of the node's outbound connections; conn.asn: their ASNs
  n <- length(conn.spy); s <- sum(conn.spy)
  uniform.p <- s / n                                                  # P(a given stem is adversary)
  uniform.any <- if (n >= 2) 1 - choose(n - s, 2) / choose(n, 2) else uniform.p   # P(at least one of 2 stems)
  share <- tapply(conn.spy, conn.asn, mean)                          # adversary share within each ASN
  k <- length(share)
  diverse.p <- mean(share)
  diverse.any <- if (k >= 2) {
    pairs <- combn(k, 2)
    mean(1 - (1 - share[pairs[1, ]]) * (1 - share[pairs[2, ]]))
  } else uniform.any                                                 # one ASN: both stems drawn from it
  # intermediate rule: weight each connection by n_asn^-alpha (alpha 0 = current rule, 1 = ASN-diverse)
  n.asn <- as.numeric(table(conn.asn)[as.character(conn.asn)])
  alpha.p <- sapply(c(0.25, 0.5, 0.75), function(al) { w <- n.asn^-al; sum(w * conn.spy) / sum(w) })
  c(uniform.p = uniform.p, uniform.any = uniform.any, diverse.p = diverse.p, diverse.any = diverse.any,
    alpha25.p = alpha.p[1], alpha50.p = alpha.p[2], alpha75.p = alpha.p[3])
}

res <- list()
for (grouping in c("s24", "asn")) {
  set.seed(314)
  net <- gen.network.grouped(d, grouping, n.unreachable = 0, compute.network.stats = FALSE)
  nd <- net$nodes
  asn.idx <- c(d$asn)          # reachable rows come first in simulated.nodes, in the order of d
  e <- net$edgelist
  e[, spy := nd$malicious[match(destination, nd$index)]]
  e[, asn := asn.idx[destination]]
  per <- e[, as.list(stem.exposure(spy, asn)), by = origin]
  # C: expected stem traffic each destination receives (sum over originators of its per-stem selection probability)
  e[, n.out := .N, by = origin]
  e[, n.asn := .N, by = .(origin, asn)]
  e[, k.asn := uniqueN(asn), by = origin]
  e[, w.cur := 1 / n.out]
  e[, w.div := 1 / (k.asn * n.asn)]
  load <- e[spy == FALSE, .(cur = sum(w.cur), div = sum(w.div)), by = destination]
  load <- merge(load, data.table(destination = seq_along(asn.idx), asn = asn.idx), by = "destination")
  hon.per.asn <- d[label == "honest", .N, by = asn]
  load <- merge(load, hon.per.asn, by = "asn", all.x = TRUE)
  gini <- function(x) { x <- sort(x); n <- length(x); sum((2 * seq_len(n) - n - 1) * x) / (n * sum(x)) }
  ld <- data.table(dataset = dataset, scenario = scenario, grouping = grouping,
    cur.median = median(load$cur), cur.p99 = quantile(load$cur, 0.99), cur.max = max(load$cur), cur.gini = gini(load$cur),
    div.median = median(load$div), div.p99 = quantile(load$div, 0.99), div.max = max(load$div), div.gini = gini(load$div),
    cur.alone = load[N == 1, mean(cur)], div.alone = load[N == 1, mean(div)],
    cur.big = load[N >= 10, mean(cur)], div.big = load[N >= 10, mean(div)])
  fwrite(ld, paste0("results/stemload_", dataset, "_", scenario, "_", grouping, ".csv"))
  res[[grouping]] <- data.table(dataset = dataset, scenario = scenario, grouping = grouping,
    outbound.spy = e[, sum(spy) / uniqueN(origin)],
    per[, lapply(.SD, mean), .SDcols = c("uniform.p", "uniform.any", "diverse.p", "diverse.any", "alpha25.p", "alpha50.p", "alpha75.p")])
  message(dataset, " ", scenario, " ", grouping, " ", paste(round(unlist(res[[grouping]][, -(1:3)]), 4), collapse = " "))
}
fwrite(rbindlist(res), paste0("results/stem_", dataset, "_", scenario, ".csv"))
