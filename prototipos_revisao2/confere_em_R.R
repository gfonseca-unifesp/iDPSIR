# Conferencia em R dos valores de referencia do ROADMAP_REVISAO2_iDPSIR.md
# contra o motor real (R/sufficiency.R, R/temporal.R). Nao faz parte do app.
# Rodar da raiz do repositorio:  Rscript prototipos_revisao2/confere_em_R.R
# Conferido em 29/09/2026 contra main @ 201d131 (R 4.5.1).

repo <- normalizePath(".")
setwd(file.path(repo, "tests/testthat"))
suppressMessages(source("helper-setup.R"))
setwd(repo)

mk <- function(ids, cats, E, sr = NULL, th = NULL) {
  nodes <- data.frame(id = ids, label = ids, dpsir_category = cats, subsystem = "",
                      uncertainty = "medium", controllability = "medium", stringsAsFactors = FALSE)
  edges <- data.frame(from = sapply(E, `[[`, 1), to = sapply(E, `[[`, 2),
                      weight = as.numeric(sapply(E, `[[`, 3)), confidence = 1,
                      interaction_type = ifelse(sapply(E, `[[`, 4) == "neg", "negative", "positive"),
                      evidence_type = "expert_assessment", stringsAsFactors = FALSE)
  g <- build_igraph(normalize_dpsir_nodes(nodes), normalize_dpsir_edges(edges), get_default_dpsir_schema())
  if (!is.null(sr)) { v <- setNames(rep(0, length(ids)), ids); v[names(sr)] <- unlist(sr); V(g)$self_regulation <- v[V(g)$name] }
  if (!is.null(th)) { v <- setNames(rep(NA_real_, length(ids)), ids); v[names(th)] <- unlist(th); V(g)$activation_threshold <- v[V(g)$name] }
  g
}
pv <- function(g, ...) { a <- list(...); p <- setNames(rep(0, vcount(g)), V(g)$name); p[names(a)] <- unlist(a); p }

ids <- c("P", "E", "I", "R"); cats <- c("Pressure", "State", "Impact", "Response")
chain <- list(list("P","E",1,"neg"), list("E","I",1,"neg"), list("R","P",1,"neg"))

cat("== teste_psir A (static, c=0.5)\n")
g <- mk(ids, cats, chain); s <- sufficiency(g, pv(g, P = 1), pv(g, R = 1), c = 0.5); print(s)

cat("\n== A6 temporal\n")
show <- function(lbl, g, mR, ws) {
  r <- simulate_temporal_pair(g, pv(g, P = 1), pv(g, R = 1), windows = max(ws), mode_D = "permanent", mode_R = mR)
  cat(sprintf("%-40s lambda=%.3f  ", lbl, r$stability$lambda))
  cat(paste(sprintf("t%d: base=%.4f scen=%.4f", ws, r$baseline[ws + 1, "I"], r$scenario[ws + 1, "I"]), collapse = " | "), "\n")
  invisible(r)
}
show("impulse, no SR", mk(ids, cats, chain), "impulse", c(5, 10, 30))
show("permanent, no SR", mk(ids, cats, chain), "permanent", c(5, 8, 10))
r <- show("impulse, SR 0.3 P,E,I", mk(ids, cats, chain, sr = list(P = .3, E = .3, I = .3)), "impulse", c(10, 30))
g <- mk(ids, cats, chain, sr = list(P = .3, E = .3, I = .3))
tt <- format_temporal_table(g, r); print(tt[tt$window == 30, ])
cat("5% tol neutral at t30? ", abs(r$scenario[31, "I"]) <= 0.05 * abs(r$baseline[31, "I"]), "\n")

cat("\n== B3 Levins vs propagate (PDF sec.4)\n")
A <- matrix(c(-.5,0,0,0, -.8,-.6,0,0, 0,.9,-.7,0, -.5,.4,0,-.7), 4, byrow = TRUE, dimnames = list(c("P","S","I1","I2"), c("P","S","I1","I2")))
u <- c(P = 1, S = 0, I1 = 0, I2 = 0)
lev <- -solve(A, u); cat("Levins:", round(lev, 3), " D:", round(abs(lev[3:4]) / max(abs(lev[3:4])), 2), "\n")
W <- A; diag(W) <- 0
for (cc in c(.5, .8, .95)) { ph <- propagate(W, u, cc); cat("propagate c=", cc, ":", round(ph[3:4], 3), " D:", round(abs(ph[3:4]) / max(abs(ph[3:4])), 2), "\n") }

cat("\n== Fase C gatilho (propagate sem gate, sanity)\n")
ids5 <- c("P1","P2","S","I","R"); cats5 <- c("Pressure","Pressure","State","Impact","Response")
base <- list(list("P1","S",.3,"neg"), list("P2","S",.3,"neg"), list("S","I",.8,"neg"))
g <- mk(ids5, cats5, c(base, list(list("R","P1",.5,"neg"))), th = list(S = .4))
print(sufficiency(g, pv(g, P1 = 1, P2 = 1), pv(g, R = 1)))

cat("\n== q7: temporal gate (current engine = state_level) P1 alone 0.3 impulse\n")
g <- mk(ids5, cats5, c(base, list(list("R","P1",.8,"neg"))), th = list(S = .4))
r <- simulate_temporal_pair(g, pv(g, P1 = 1), pv(g), windows = 6, mode_D = "impulse", mode_R = "impulse")
print(round(r$baseline[, c("P1","S","I")], 3)); cat("lambda", r$stability$lambda, "\n")

cat("\n== crescimento D->P w=.5 g=.1 impulse\n")
g <- mk(c("D","P"), c("Driver","Pressure"), list(list("D","P",.5,"pos")))
V(g)$growth_rate <- c(D = .1, P = 0)[V(g)$name]
r <- simulate_temporal_pair(g, pv(g, D = 1), pv(g), windows = 4, mode_D = "impulse")
print(r$baseline)

cat("\n== D2: tendencia exogena com entrada constante ref*g (g = 0.1, ref = 1, sem push)\n")
g <- mk(c("D","P"), c("Driver","Pressure"), list(list("D","P",.5,"pos")))
V(g)$growth_rate <- c(D = .1, P = 0)[V(g)$name]
r <- simulate_temporal_pair(g, pv(g, D = 0.1), pv(g), windows = 3, mode_D = "permanent")  # motor real, push constante = ref*g
cat(sprintf("t%d: x_D=%.4f  w*x_D=%.4f\n", 1:3, r$baseline[2:4, "D"], 0.5 * r$baseline[2:4, "D"]))
# Esperado: 0.05 / 0.105 / 0.1655 (D5)

cat("\n== A2/A6: criterio de parada 'ate neutralizar' (D1/D2 revisadas, 29/09)\n")
# Para na primeira janela em que o Impacto piora no baseline e o cenario chega a <= tol_abs.
ids <- c("P","E","I","R"); cats <- c("Pressure","State","Impact","Response")
chain <- list(list("P","E",1,"neg"), list("E","I",1,"neg"), list("R","P",1,"neg"))
for (sr in list(NULL, list(P=.3,E=.3,I=.3))) for (mD in c("permanent","impulse")) for (mR in c("permanent","impulse")) {
  g <- mk(ids, cats, chain, sr = sr)
  r <- simulate_temporal_pair(g, pv(g, P=1), pv(g, R=1), windows = 50, mode_D = mD, mode_R = mR)
  b <- r$baseline[-1,"I"]; s <- r$scenario[-1,"I"]
  t_stop <- which(b > 1e-9 & s <= 1e-9)[1]
  rel5 <- which(abs(b) > 1e-9 & abs(s) <= 0.05*abs(b))[1]
  cat(sprintf("SR=%-3s P=%-9s R=%-9s  para em t=%-3s I=%-7s | 5%% relativo em t=%s\n", if(is.null(sr))"0" else ".3", mD, mR,
      t_stop, if (is.na(t_stop)) "-" else round(s[t_stop], 2), rel5))
}
