# Pre-registration — simulated DPSIR networks: what does parameterization change?

**Status:** registered before any simulation was run (Revisão 3, E5.1). The git commit that
adds this file precedes every file in `out/`; the order can be checked with
`git log --follow analysis/sim_networks/PREREGISTRO.md analysis/sim_networks/out`.
Any later change to this plan is recorded in the section *Deviations* at the end, with its
date and reason. Hypotheses, conditions and analyses below are not to be adjusted to results.

**Code:** `generate.R` (networks), `run.R` (conditions), `analyze.R` (analysis), all calling the
app's own engine (`R/structural.R`, `R/sufficiency.R`, `R/triggers.R`, `R/relevance.R`,
`R/temporal.R`); nothing is reimplemented. Software version: the commit of this file.

## 1. Question

In plausible DPSIR networks, how often do the sufficiency verdict of each Impact and the
priority order of the Impacts change between the *raw* network (structure and signs only,
every setting at the app's default — the "first run") and *parameterized* versions of the
same network? Which parameters, and which network properties, explain the changes?

## 2. Networks (generator, `generate.R`)

One network per seed `1000 + i`, `i = 1..N`. Specification (fixed here):

- **Levels and roles:** the app's default schema (Driver, Pressure, State, Impact, Response).
- **Size:** D ~ U{2..5}, P ~ U{2..6}, S ~ U{2..6}, I ~ U{2..6}, R ~ U{1..5}; redrawn until the
  total is 10–25 nodes.
- **Edges:** only those allowed by the schema (D→P, P→S, S→I, I→R, R→{D,P,S,I}); **no
  State→State** (and no other same-level edge). For each allowed level pair a density
  d ~ U(0.15, 0.5) is drawn and each possible edge is included with probability d.
  Repairs, in this order: every Pressure gets ≥ 1 incoming Driver edge, every State ≥ 1
  incoming Pressure edge, every Impact ≥ 1 incoming State edge (so every Impact is reachable
  from some Driver); every Response gets ≥ 1 outgoing edge to D, P, S or I.
- **Feedback loops:** the network draws q ∈ {0, 0.3, 0.6} (equal probability); each Response
  receives an I→R edge from a random Impact with probability q. Loops exist only through
  I→R (decision D4 of the app).
- **Signs:** the default convention (manuscript Table 3): D→P +, P→S −, S→I −, I→R +,
  R→D −, R→P −, R→S +, R→I −. Each network draws f ~ U(0.10, 0.20); each State is
  harm-oriented with probability f, which flips all its edges consistently (P→S +, S→I +,
  R→S −).

## 3. Conditions (`run.R`)

For each network, the same scenario: **pressure** = every Driver at 100%; **response** = each
Response included with probability 0.5 (at least one), strength ~ U(25%, 150%) — drawn once
per network.

| Condition | Strengths (β) | State thresholds | Growth | Reading |
|---|---|---|---|---|
| **C0 raw** | every edge "moderate" (0.45), as `data-raw/first_run_build.R` | no | no | static |
| **C1 strengths** | drawn (below) | no | no | static |
| **C2 + thresholds** | as C1 | yes | no | static, with State triggers |
| **C2t temporal** | as C1 | yes | no | temporal, verdict at window T = 20 |
| **C3 + growth** | as C1 | yes | yes | temporal, verdict at window T = 20 |
| **C4 uncertainty** | C1 + `sufficiency_confidence()` with `structural = TRUE` (item E3) | — | — | confidence (secondary) |

- **Strengths (C1–C4):** R = 20 draws per network (seed `100000 · i + r`). Per draw, a mode is
  chosen with probability ½: *classes* (weak 0.15 / moderate 0.45 / strong 0.80, equal
  probability per edge) or *continuous* β ~ U(0.05, 0.9). For every target node, if the sum of
  β² over its incoming edges that do not leave a Response exceeds 0.95, those edges are
  rescaled so it equals 0.95 (the app's explained-variance rule). Uncertainty bands: the class
  band, or β ± 30% (truncated at 0) for continuous draws.
- **Thresholds (C2, C2t, C3):** drawn once per network; each State gets a threshold with
  probability 0.3, at |z| ~ U(0.2, 1.5) standard deviations from its initial level, in the
  direction the pressure moves it (falling for a natural-condition State, rising for a
  harm-oriented one).
- **Growth (C3):** drawn once per network; each Driver grows with probability 0.3 at
  g ~ U(0.01, 0.05) per window; half of the growing Drivers have a ceiling at (1 + U(0.2, 1))
  times the initial level.
- **Temporal settings (C2t, C3):** pressure and response added every window; fixed 20 windows;
  self-regulation 1 on Drivers, Pressures and Responses (levels set by the scenario, as in the
  app's examples) and the app's default 0.5 on States and Impacts; trigger by accumulated
  State level (the app's default).
- **Impact values (prioritization):** each Impact's endpoint class is ecological, service or
  welfare with equal probability; v = 1 for ecological, v ~ U(0.2, 1) otherwise. Used in every
  condition (C0 included), so priorities differ only through the network readings.

## 4. Outcomes

**Verdict of an Impact** (primary, 3 levels): *neutralized* (net ≤ 0 and worsened by the
pressure), *not neutralized* (worsened, net > 0), *not affected* (not worsened by the
pressure). Temporal conditions: at window 20, "Neutralized", "Neutralized (relative)" (5%
tolerance) and "Improved beyond neutral" → neutralized; "Partial" and "Failure/worsened" →
not neutralized; "Not affected" → not affected. Secondary, 5 levels: neutralized, partly
covered, not covered, worsened by the response, not affected (the rules of
`interpret_scenario()`).

**Primary outcomes:**
1. **Verdict change** per Impact between two conditions (3-level verdict differs).
2. **Top-priority change** per network: the Impact with the highest priority differs.
3. **Kendall's τ** between the priority orders of two conditions (worsened Impacts only;
   networks with fewer than 3 worsened Impacts in either condition are left out of τ).

**Recorded per network:** number of nodes, density, number of directed cycles (and whether
any exists), mean shortest D→I path length, ρ(B), share of Impacts reached by the active
responses, number of States with a threshold, number of growing Drivers.
**Recorded per Impact:** worsening, mitigation, net, verdict (3 and 5 levels), strength to
neutralize, priority and rank; C0 closeness to neutralization c = |net| / worsening.

## 5. Hypotheses

- **H1.** Changing only the strengths changes a moderate share of verdicts: the proportion of
  Impact verdicts that differ between C0 and C1 is **below 30%**.
- **H2.** Thresholds and growth change verdicts more than strengths do: the change rates
  **C1→C2** (thresholds) and **C2t→C3** (growth) are each **higher** than **C0→C1**.
- **H3.** Networks with feedback loops (any I→R edge closing a cycle) change **more** verdicts
  C0→C1 than acyclic networks.
- **H4.** Changes concentrate on Impacts close to neutralization in the raw network: Impacts
  with c < 0.2 in C0 change verdict C0→C1 **more often** than the others.
- **H5.** The priority order is more stable than the verdicts: mean Kendall's τ between C0 and
  C1 is **above 0.7**.

## 6. Analysis (`analyze.R`)

- Proportions with 95% confidence intervals by **bootstrap over networks** (2000 resamples,
  seed 42), for every pair C0→C1, C1→C2, C2→C2t, C2t→C3, C0→C3.
- H1: the upper bound of the 95% CI of the C0→C1 change rate below 0.30 → confirmed; lower
  bound above 0.30 → refuted; otherwise inconclusive.
- H2: paired bootstrap (same networks and draws) of the differences of change rates; each
  difference with a 95% CI entirely above 0 → confirmed; entirely below → refuted; otherwise
  inconclusive. H2 is confirmed only if both differences are.
- H3, H4: mixed-effects logistic regression of "verdict changed C0→C1" (per Impact and draw)
  on network properties, with a random intercept per network (`lme4::glmer`, binomial, logit):
  fixed effects has_cycle, c < 0.2, n_nodes, density, ρ(B), mean D→I path length,
  share reached. H3 / H4: the coefficient's 95% Wald CI entirely above 0 → confirmed;
  entirely below → refuted; otherwise inconclusive.
- H5: mean τ with bootstrap 95% CI; lower bound above 0.7 → confirmed; upper bound below
  0.7 → refuted; otherwise inconclusive.
- **Exploratory** (not hypothesis tests): random forest (`ranger`, 500 trees, permutation
  importance) of "verdict changed" on the network properties and the draw mode; the same
  tables for the 5-level verdict; C4 confidence distributions.

## 7. Sample size and exclusions

- **N = 1000 networks × R = 20 strength draws** (20,000 evaluations per condition). Timing
  is measured on 50 networks first; if the full run is estimated above 24 h on the authors'
  machine, N is reduced — never below 500 — and the reduction is recorded under
  *Deviations* before running.
- **Excluded, and counted:** networks whose raw version (C0) has ρ(B) ≥ 1 (the static reading
  does not exist); strength draws with ρ(B) ≥ 1 after rescaling (redrawn up to 5 times, then
  counted as rejected); temporal runs (C2t, C3) whose update diverges (ρ((I − S) + B) ≥ 1),
  counted separately — those draws are left out of the temporal comparisons only.
- Rejection rates are reported, as they characterize which parameterizations the static
  reading cannot handle.

## 8. Reproducibility

Seeds as above; `with_local_seed()` for every random draw; `run.R` writes one row per
network × draw × condition × Impact to `out/results.csv.gz` and the network properties to
`out/networks.csv`; `analyze.R` reads only those files. One command runs everything:
`Rscript analysis/sim_networks/run_all.R`.

## Deviations

**2026-09-30, before any run of the conditions (clarifications of points the plan left open):**
1. The number of simulations for the reliability ρ (prioritization) and for C4 is 300, the
   app's default. Timing on 3 networks: 43 s per network in one process, i.e. about 40 min
   for N = 1000 on 20 parallel processes - well under the 24 h limit, so N stays at 1000.
2. Parallelism uses base R `parallel` (PSOCK cluster, each worker loading the app's engine)
   instead of `future.apply`; seeds are per network, so results do not depend on the
   number of workers.
3. Priority and rank exist only in the static conditions (C0, C1, C2): the temporal reading
   has no prioritization. H5 and the top-priority outcome compare C0 with C1, as planned.
4. The timing run (50 networks) writes to `out_timing/`, not `out/`, and is not analysed.
   Measured: 4.0 min for 50 networks on 20 processes (about 80 min for 1000).
5. The timing run found one case the plan did not foresee: closing a State trigger zeroes
   edges, and in a signed matrix removing an edge can raise rho above 1 (it removes a
   cancellation). The app's resampling now skips such draws, as it does for rho(B) >= 1
   (fixed in the app, with a test). In the experiment, a condition whose base reading
   cannot be computed for this reason is counted (`conditions_failed` in `counts.csv`) and
   left out of the comparisons that use it; the rest of the network is kept.
