# Simulated DPSIR networks - one command for the whole experiment (E5).
# Run from the repository root:
#   Rscript analysis/sim_networks/run_all.R [N] [workers] [out_dir]
# Defaults: N = 1000 networks, workers = 20, out_dir = analysis/sim_networks/out.
args <- commandArgs(trailingOnly = TRUE)
N <- if (length(args) >= 1) as.integer(args[1]) else 1000L
workers <- if (length(args) >= 2) as.integer(args[2]) else 20L
out_dir <- if (length(args) >= 3) args[3] else "analysis/sim_networks/out"

setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")
source("analysis/sim_networks/generate.R")
source("analysis/sim_networks/run.R")
source("analysis/sim_networks/analyze.R")

t0 <- Sys.time()
run_experiment(seq_len(N), R = 20, n_rho = 300, n_conf = 300, workers = workers, out_dir = out_dir)
cat(sprintf("Conditions: %d networks in %.1f min\n", N, as.numeric(Sys.time() - t0, units = "mins")))
a <- analyze_all(out_dir)
print(a$hypotheses)
