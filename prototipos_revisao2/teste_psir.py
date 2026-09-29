# Porta fiel de build_signed_matrix/spectral_radius/propagate/sufficiency (R/sufficiency.R)
import numpy as np
nodes=["P","E","I","R"]; ix={n:i for i,n in enumerate(nodes)}
def W_of(edges):
    W=np.zeros((4,4))
    for f,t,w,s in edges: W[ix[t],ix[f]]+= (-1 if s=="neg" else 1)*w   # A[to,from]
    return W
def rho(W): return 0.0 if np.all(W==0) else max(abs(np.linalg.eigvals(W)))
def propagate(W,p,c=.5):
    r=rho(W); lam = c if r<1e-12 else c/r      # igual ao R (rho==0 -> lambda=c)
    return np.linalg.solve(np.eye(4)-lam*W,p)-p, lam, r
def suff(edges,pP=1.0,pR=1.0,c=.5):
    W=W_of(edges); pD=np.zeros(4); pD[ix["P"]]=pP; pr=np.zeros(4); pr[ix["R"]]=pR
    wr,lam,r=propagate(W,pD,c); mt,_,_=propagate(W,pr,c)
    wo,mi=wr[ix["I"]],mt[ix["I"]]; net=wo+mi
    need = wo/(-mi)*pR if mi<0 else float("nan")
    return dict(rho=r,lam=lam,piora=wo,mitig=mi,liquido=net,neutraliza=net<=1e-9,forca_necessaria=need, P_R=mt[ix["P"]])
base=[("P","E",1,"neg"),("E","I",1,"neg"),("R","P",1,"neg")]
casos={
 "A. Cadeia simples (sem ciclo), pesos 1":base,
 "B. + retroalimentação I→R forte (peso 1)":base+[("I","R",1,"pos")],
 "C. + retroalimentação I→R fraca (peso 0,001)":base+[("I","R",0.001,"pos")],
 "D. Cadeia simples, pesos 3":[(f,t,3,s) for f,t,_,s in base],
}
for k,e in casos.items():
    r=suff(e); print(k); print("  "+", ".join(f"{a}={b:.4g}" if isinstance(b,float) else f"{a}={b}" for a,b in r.items()))
# Ideal: resposta cancela exatamente a pressão -> efeito direto de R em P deveria ser -1
