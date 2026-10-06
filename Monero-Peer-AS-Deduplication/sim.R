# Simulation of outbound peer selection with /24 deduplication (monero master) and with
# ASN deduplication (monero PR #11474, --asmap). Adapted from xmrpeers::gen.network() by Rucknium
# (https://github.com/Rucknium/xmrpeers/blob/main/R/peer-selection.R).
#
# Differences from gen.network():
#  1. The two subnet keys (already.connected.subnet, deduplication.subnet) are replaced by one
#     `group` key, because monero master and PR #11474 use the same key for both steps:
#     get_peer_group() returns the /24 (master) or the ASN (--asmap) and it is used both to build
#     connected_groups and to deduplicate candidates (src/p2p/net_node.inl, make_new_connection_from_peerlist).
#  2. The draw "shuffle candidates, keep the first candidate of each group not already connected,
#     pick one uniformly" is computed as "pick an allowed group uniformly, then a member of that
#     group uniformly". The two are the same distribution: after the shuffle each group is
#     represented by a uniformly random member and the final pick is uniform over representatives.
#     choose.peer.reference() below is the literal gen.network() version, used by check.equivalence().
#
# Input: data.table with columns ip, s24, asn, label ("honest" or not), from build_dataset.py.

library(data.table)

group.key <- function(nodes, grouping) {
  switch(grouping,
    s24 = paste0("s24:", nodes$s24),
    # hybrid (not in PR #11474): /24 deduplication as in master, plus at most one outbound
    # connection per ASN. The draw group is the /24; the ASN cap is applied in choose.peer()
    hybrid = paste0("s24:", nodes$s24),
    # PR #11474: unmapped addresses (asn 0) fall back to their /24
    asn = ifelse(nodes$asn != 0, paste0("asn:", nodes$asn), paste0("s24:", nodes$s24)),
    stop("unknown grouping"))
}

gen.network.grouped <- function(nodes, grouping, n.unreachable = 0,
  default.outbound.connections = 12, dropped.connection.churns = 12,
  compute.network.stats = TRUE) {

  reach <- copy(nodes)
  reach[, group := group.key(reach, grouping)]
  reach[, malicious := label != "honest"]
  reach[, reachable := TRUE]

  simulated.nodes <- rbind(
    reach[, .(ip, group, malicious, reachable)],
    data.table(ip = rep(NA_character_, n.unreachable), group = rep(NA_character_, n.unreachable),
      malicious = rep(FALSE, n.unreachable), reachable = rep(FALSE, n.unreachable)))
  simulated.nodes[, index := seq_len(.N)]

  # members of each group, as indices into simulated.nodes
  members <- split(simulated.nodes[reachable == TRUE, index], simulated.nodes[reachable == TRUE, group])
  group.names <- names(members)
  group.of <- simulated.nodes$group
  # ASN of each draw group (a /24 is inside one ASN in this data), used by the hybrid ASN cap
  asn.of.node <- c(reach$asn, rep(NA, n.unreachable))
  asn.of.group <- asn.of.node[sapply(members, `[`, 1)]

  choose.peer <- function(result) {
    current <- result[!is.na(result) & result > 0]
    connected <- unique(group.of[current])
    allowed <- group.names[!group.names %in% connected]
    if (grouping == "hybrid") {
      allowed <- allowed[!asn.of.group[match(allowed, group.names)] %in% asn.of.node[current]]
    }
    g <- allowed[sample.int(length(allowed), 1)]
    m <- members[[g]]
    m[sample.int(length(m), 1)]
  }

  non.malicious.indices <- simulated.nodes[malicious == FALSE, index]

  connections <- lapply(non.malicious.indices, function(i) {
    result <- integer(default.outbound.connections)
    for (j in seq_len(default.outbound.connections)) result[j] <- choose.peer(result)
    for (churn.iter in seq_len(dropped.connection.churns)) {
      dropped.connection <- sample(default.outbound.connections, 1)
      result[dropped.connection] <- NA
      result[dropped.connection] <- choose.peer(result)
    }
    result
  })

  edgelist <- data.table(origin = rep(non.malicious.indices, lengths(connections)),
    destination = unlist(connections))

  inbound <- edgelist[, .(n.inbound = .N), by = .(index = destination)]
  simulated.nodes <- merge(simulated.nodes, inbound, by = "index", all.x = TRUE)
  simulated.nodes[is.na(n.inbound), n.inbound := 0L]

  edgelist[, malicious.connection := destination %in% simulated.nodes[malicious == TRUE, index]]
  mal <- edgelist[, .(n.malicious.outbound = sum(malicious.connection)), by = .(index = origin)]
  edgelist[, malicious.connection := NULL]
  simulated.nodes <- merge(simulated.nodes, mal, by = "index", all.x = TRUE)
  simulated.nodes[is.na(n.malicious.outbound), n.malicious.outbound := 0L]

  result <- list(nodes = simulated.nodes, edgelist = edgelist)

  if (compute.network.stats && requireNamespace("igraph", quietly = TRUE)) {
    g <- igraph::graph_from_edgelist(as.matrix(edgelist), directed = TRUE)
    s <- list()
    s$centr_betw <- igraph::centr_betw(g, directed = FALSE)
    s$centr_clo <- igraph::centr_clo(g, mode = "all")
    if (any(!is.finite(s$centr_clo$res))) {
      s$centr_clo$centralization <- igraph::centralize(na.omit(s$centr_clo$res),
        theoretical.max = s$centr_clo$theoretical_max)
    }
    s$centr_degree <- igraph::centr_degree(g, mode = "all")
    s$centr_eigen <- igraph::centr_eigen(g, directed = FALSE)
    result$network.stats <- s
  }
  result
}

# Literal gen.network() draw (shuffle, unique by group, sample) for the equivalence check
choose.peer.reference <- function(reach, result) {
  possible <- reach[!group %in% reach$group[match(result, reach$index)], ]
  possible <- possible[sample(.N), ]
  possible <- unique(possible, by = "group")
  sample(possible$index, 1)
}

# Compare the distribution of the first draw with 3 peers already connected, for both methods
check.equivalence <- function(nodes, grouping, n = 20000, seed = 1) {
  set.seed(seed)
  reach <- copy(nodes)
  reach[, group := group.key(reach, grouping)]
  reach[, malicious := label != "honest"]
  reach[, index := seq_len(.N)]
  members <- split(reach$index, reach$group)
  connected.idx <- sample(reach$index, 3)
  allowed <- setdiff(names(members), reach$group[connected.idx])
  fast <- replicate(n, { m <- members[[allowed[sample.int(length(allowed), 1)]]]; m[sample.int(length(m), 1)] })
  ref <- replicate(n, choose.peer.reference(reach, connected.idx))
  c(fast.malicious.share = mean(reach$malicious[fast]), reference.malicious.share = mean(reach$malicious[ref]),
    exact.malicious.share = {
      # analytic: mean over allowed groups of the malicious share inside the group
      mean(sapply(members[allowed], function(m) mean(reach$malicious[m])))
    })
}
