# Simulated DPSIR networks - results against the pre-registration

Networks: 1000 generated, 0 excluded (raw rho(B) >= 1), 0 errors. Strength draws rejected: 0. Temporal runs diverged: 2360.

## Hypotheses

| Hypothesis | Statistic | Estimate | 95% CI | Result |
|---|---|---|---|---|
| H1 | change rate C0->C1 | 0.159 | 0.151 - 0.165 | **confirmed** |
| H2 (thresholds) | rate(C1->C2) - rate(C0->C1) | 0.030 | 0.014 - 0.048 | **confirmed** |
| H2 (growth) | rate(C2t->C3) - rate(C0->C1) | -0.116 | -0.124 - -0.108 | **refuted** |
| H2 | both H2 differences | - | - - - | **refuted** |
| H3 | glmer coef has_cycle | -0.239 | -0.420 - -0.057 | **refuted** |
| H4 | glmer coef near (c < 0.2) | 1.691 | 1.625 - 1.757 | **confirmed** |
| H5 | mean Kendall tau C0 vs C1 | 0.636 | 0.620 - 0.654 | **refuted** |

## Verdict change rates (3 levels)

| Pair | n | Rate | 95% CI |
|---|---|---|---|
| C0->C1 | 80340 | 0.159 | 0.151 - 0.165 |
| C1->C2 | 80328 | 0.189 | 0.174 - 0.205 |
| C2->C2t | 75749 | 0.178 | 0.167 - 0.190 |
| C2t->C3 | 75761 | 0.043 | 0.038 - 0.047 |
| C0->C3 | 75761 | 0.228 | 0.219 - 0.238 |

Top-priority change C0->C1: 35.3% of network x draw pairs with >= 3 worsened Impacts.
