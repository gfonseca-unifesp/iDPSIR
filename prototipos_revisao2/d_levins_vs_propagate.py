# Fase B / decisao D14: compara a importancia dinamica D pelo equilibrio de Levins (PDF v1.0, secao 4)
# com a propagacao do iDPSIR (propagate(), R/sufficiency.R). Rede P, S, I1, I2 do exemplo do PDF.
import numpy as np
A=np.array([[-.5,0,0,0],[-.8,-.6,0,0],[0,.9,-.7,0],[-.5,.4,0,-.7]])   # linhas/colunas: P, S, I1, I2
u=np.array([1,0,0,0])
lev=-np.linalg.solve(A,u)
print("autovalores de A:",np.linalg.eigvals(A).round(3))
print("Levins     delta I1, I2 =",lev[2:].round(3)," D =",(abs(lev[2:])/abs(lev[2:]).max()).round(2))
W=A.copy(); np.fill_diagonal(W,0)          # build_signed_matrix(): zera a diagonal
for c in (.3,.5,.8,.95):                     # rede aciclica -> lambda = c
    phi=np.linalg.solve(np.eye(4)-c*W,u)-u
    d=abs(phi[2:]); print(f"propagate c={c}: delta I1, I2 =",phi[2:].round(3)," D =",(d/d.max()).round(2))
