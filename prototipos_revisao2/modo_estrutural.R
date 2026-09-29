# Conferencias em R do modo estrutural (anexo X2/X3 do ROADMAP_REVISAO2_iDPSIR.md).
# Nao usa o codigo do app; so R base. Rodar: Rscript prototipos_revisao2/modo_estrutural.R

cat("== X2.1: slope x r2 x beta padronizado\n")
set.seed(1); n <- 5000
cases <- list(A=c(b=.5,sdx=1,sde=.1), B=c(b=.5,sdx=1,sde=2), C=c(b=.5,sdx=.2,sde=.5), D=c(b=.05,sdx=1,sde=.01))
for (k in names(cases)) { p <- cases[[k]]; x <- rnorm(n,0,p["sdx"]); y <- p["b"]*x + rnorm(n,0,p["sde"])
  f <- lm(y~x); r2 <- summary(f)$r.squared; beta <- coef(f)[2]*sd(x)/sd(y)
  cat(sprintf("%s: b=%.3f  r2=%.3f  beta_std=%.3f  efeito de +1 unid. em x: %+.3f em y\n", k, coef(f)[2], r2, beta, coef(f)[2])) }
# invariancia: B_raw vs B_std (similaridade diagonal)
n2 <- c("P","S","I"); Bs <- matrix(0,3,3,dimnames=list(n2,n2)); Bs["S","P"] <- -.7; Bs["I","S"] <- -.6; Bs["P","I"] <- .3  # com ciclo
sdv <- c(P=2, S=10, I=0.5); Sm <- diag(sdv); Br <- Sm %*% Bs %*% solve(Sm)
cat("rho std:", max(Mod(eigen(Bs)$values)), " rho raw:", max(Mod(eigen(Br)$values)), "\n")
tot <- function(B,p) solve(diag(3)-B,p)-p
cat("efeito total de +1 DP em P sobre I (std):", tot(Bs,c(1,0,0))[3], " | via raw (+2 unid. em P), convertido p/ DP de I:", tot(Br,c(2,0,0))[3]/sdv["I"], "\n")

cat("\n== X2.4: exemplo P1->S, P2->S, S->I, R->P1 (efeitos totais em DP)\n")
nn <- c("P1","P2","S","I","R"); Bx <- matrix(0,5,5,dimnames=list(nn,nn))
Bx["S","P1"] <- -.7; Bx["S","P2"] <- -.5; Bx["I","S"] <- -.6; Bx["P1","R"] <- -.8
te <- function(B,p) as.numeric(solve(diag(nrow(B))-B,p)-p)
cat("P1->I:", te(Bx,c(1,0,0,0,0))[4], " R->I:", te(Bx,c(0,0,0,0,1))[4], "\n")
x <- rep(0,5); for (t in 1:5) { x <- as.numeric(Bx %*% x) + c(1,0,0,0,0) }
cat("temporal a=0, P1 permanente: I(5) =", x[4], "(igual ao estatico)\n")

cat("\n== X3.1: modo estrutural = Levins padronizado (exemplo sec. 4 do PDF v1.0)\n")
nm <- c("P","S","I1","I2")
A <- matrix(c(-.5,0,0,0, -.8,-.6,0,0, 0,.9,-.7,0, -.5,.4,0,-.7), 4, byrow=TRUE, dimnames=list(nm,nm))
u <- c(1,0,0,0)
lev <- -solve(A,u)
d <- abs(diag(A)); B <- A/d; diag(B) <- 0          # beta_ij = a_ij/|a_ii|
sm <- solve(diag(4)-B, u/d)                          # press escalado por 1/|a_ii|
cat("Levins  :", round(lev,3), " D(I1,I2):", round(abs(lev[3:4])/max(abs(lev[3:4])),2), "\n")
cat("Estrut. :", round(sm,3),  " D(I1,I2):", round(abs(sm[3:4])/max(abs(sm[3:4])),2), "\n")
cat("rho(B):", round(max(Mod(eigen(B)$values)),3), "\n")
# modo estrutural 'ingenuo' (beta = a_ij, sem escalar pela autorregulacao)
B2 <- A; diag(B2) <- 0; s2 <- solve(diag(4)-B2,u)-u
cat("Estrut. beta=a_ij:", round(s2,3), " D:", round(abs(s2[3:4])/max(abs(s2[3:4])),2), "\n")

cat("
== C1: gatilho no modo estrutural (limiar z = -0,4 em S)
")
nm <- c("P1","P2","S","I","R")
run <- function(bRP1, pP1, pP2, pR, z = -0.4) {
  B <- matrix(0,5,5,dimnames=list(nm,nm)); B["S","P1"] <- -.3; B["S","P2"] <- -.3; B["I","S"] <- -.8; B["P1","R"] <- -bRP1
  p <- c(pP1,pP2,0,0,pR)
  lev <- solve(diag(5)-B, p); lev[1:2] <- pmax(lev[1:2], 0)   # D/P recortados em >= 0 (D7)
  xS <- sum(B["S",] * lev); open <- if (z < 0) xS <= z else xS >= z
  Bg <- B; if (!open) Bg[, "S"] <- 0
  phi <- solve(diag(5)-Bg, p) - p
  c(S = round(xS,3), aberto = open, I = round(phi[4],3))
}
casos <- list("1 so P1"=c(.5,1,0,0), "2 P1+P2"=c(.5,1,1,0), "3 P1+P2+R (b=.5)"=c(.5,1,1,1),
              "4 P1+P2+R (b=.8)"=c(.8,1,1,1), "5 P1+P2 a 70%"=c(.8,.7,.7,0), "6 P1+P2 a 60%"=c(.8,.6,.6,0))
for (k in names(casos)) { a <- casos[[k]]; cat(sprintf("%-20s %s\n", k, paste(names(run(a[1],a[2],a[3],a[4])), run(a[1],a[2],a[3],a[4]), sep="=", collapse="  "))) }

cat("
== D20: equilibrio temporal com persistencia a = 1 - sr
")
nm <- c("P","S","I"); B <- matrix(0,3,3,dimnames=list(nm,nm)); B["S","P"] <- -.7; B["I","S"] <- -.6; p <- c(1,0,0)
for (s in c(1, .5, .3, 0)) { x <- rep(0,3); for (t in 1:300) x <- (1-s)*x + as.numeric(B %*% x) + p
  eq <- if (s > 0) solve(s*diag(3) - B, p)[3] else NA
  cat(sprintf("sr=%.1f  I(300)=%.3f  equilibrio (sI-B)^-1 p = %s   estatico (I-B)^-1 p = %.3f\n", s, x[3], format(round(eq,3)), solve(diag(3)-B,p)[3])) }
cat("\n== P3/D24: crescimento separado da autorregulacao (prototipo)\n")
# D -> P (beta 0.5). Crescimento g no D: tendencia(t) = (ref/DP)*((1+g)^t - 1).
# Valor do no = desvio + tendencia. A autorregulacao age so no desvio.
sim_sep <- function(g, srD, pushD = "none", T = 4, ref_sd = 1) {
  devD <- 0; devP <- 0; out <- NULL
  for (t in 1:T) {
    xD_prev <- devD + ref_sd * ((1 + g)^(t - 1) - 1)
    pD <- if (pushD == "impulse" && t == 1) 1 else 0
    devP <- devP + 0.5 * xD_prev
    devD <- (1 - srD) * devD + pD
    xD <- devD + ref_sd * ((1 + g)^t - 1)
    out <- rbind(out, c(t = t, x_D = xD, contrib_em_P = 0.5 * xD))
  }
  round(out, 4)
}
cat("D fora do cenario, g=0.1, sr_D=0.5:\n"); print(sim_sep(.1, .5))
cat("idem com sr_D=0 (a tendencia nao depende da autorregulacao):\n"); print(sim_sep(.1, 0))
cat("impulso em D com sr_D=0.5: g=0 (col. 2-3) x g=0.1 (col. 4-5):\n")
print(cbind(sim_sep(0, .5, "impulse"), sim_sep(.1, .5, "impulse")[, 2:3]))
