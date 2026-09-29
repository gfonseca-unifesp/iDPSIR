import numpy as np
nodes=["P","E","I","R"]; ix={n:i for i,n in enumerate(nodes)}
def W_of(edges):
    W=np.zeros((4,4))
    for f,t,w,s in edges: W[ix[t],ix[f]]+=(-1 if s=="neg" else 1)*w
    return W
def rho(W): return 0.0 if np.all(W==0) else max(abs(np.linalg.eigvals(W)))
def prop(W,p,lam): return np.linalg.solve(np.eye(4)-lam*W,p)-p
chain=[("P","E",1,"neg"),("E","I",1,"neg")]
alvos={"R→P (limite de captura)":("P","neg"),"R→E (repovoamento)":("E","pos"),"R→I (compensação de renda)":("I","neg")}
pD=np.eye(4)[ix["P"]]; pR=np.eye(4)[ix["R"]]
print("== Leitura estática (sufficiency) ==")
for nome,(alvo,s) in alvos.items():
    W=W_of(chain+[("R",alvo,1,s)]); r=rho(W)
    for rot,lam in (("atual c=0,5",0.5 if r==0 else .5/r),("proposta",1.0 if r==0 else min(1,.5/r))):
        wo=prop(W,pD,lam)[ix["I"]]; mi=prop(W,pR,lam)[ix["I"]]
        print(f"  {nome:30s} {rot:12s} piora={wo:+.3f} mitig={mi:+.3f} liquido={wo+mi:+.3f} forca={wo/-mi*100:.0f}%")
print("== Simulação temporal (temporal.R, pressão permanente) ==")
for modeR in ("impulse","permanent"):
  print(" resposta:",modeR)
  for nome,(alvo,s) in alvos.items():
    W=W_of(chain+[("R",alvo,1,s)]); r=rho(W); lam=1 if r==0 else min(1,.9/r); W=lam*W
    xb=np.zeros(4); xs=np.zeros(4); linha=[]
    for t in range(1,9):
        pr=pR if (modeR=="permanent" or t==1) else 0*pR
        xb=xb+W@xb+pD; xs=xs+W@xs+pD+pr
        b,sv=xb[ix["I"]],xs[ix["I"]]
        v="Neutr" if abs(sv)<=1e-9 else ("Melhor" if sv<0 else ("Falha" if sv>=b-1e-9 else "Parcial"))
        linha.append(f"t{t}: {b:.0f}/{sv:+.0f} {v}")
    print(f"  {nome:30s} "+" | ".join(linha))
