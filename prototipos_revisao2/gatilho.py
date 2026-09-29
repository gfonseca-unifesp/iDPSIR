# Protótipo do gatilho por carga incidente no Estado (leitura estática, porta de propagate())
import numpy as np
N=["P1","P2","S","I","R"]; ix={n:i for i,n in enumerate(N)}; cat={"P1":"P","P2":"P","S":"S","I":"I","R":"R"}
TH={"S":0.4}
def W_of(E):
    W=np.zeros((5,5))
    for f,t,w,s in E: W[ix[t],ix[f]]+=(-1 if s=="neg" else 1)*w
    return W
def rho(W): return max(abs(np.linalg.eigvals(W))) if np.any(W) else 0
def propagate(W,p,c=.5):
    r=rho(W); lam=c if r<1e-12 else c/r
    return np.linalg.solve(np.eye(5)-lam*W,p)-p
def levels(W,p):
    # intensidade sem desconto, camada a camada (R -> P -> S), recortada em >= 0 para D/P
    lv=p.copy()
    for n in ("P1","P2"):
        lv[ix[n]]=max(0,p[ix[n]]+sum(W[ix[n],ix[m]]*lv[ix[m]] for m in ("R",)))
    return lv
def load(W,p,s):
    lv=levels(W,p); return abs(sum(W[ix[s],j]*lv[j] for j in range(5) if cat[N[j]] in ("P","R")))
def gated(W,p):
    Wg=W.copy(); st={}
    for s,th in TH.items():
        L=load(W,p,s); st[s]=(round(L,3),L>=th)
        if L<th: Wg[:,ix[s]]=0   # corta todas as arestas de saida do Estado
    return Wg,st
def run(nome,E,pP1,pP2,pR):
    W=W_of(E); pD=np.zeros(5); pD[ix["P1"]]=pP1; pD[ix["P2"]]=pP2
    pR_=np.zeros(5); pR_[ix["R"]]=pR
    Wd,sd=gated(W,pD); worse=propagate(Wd,pD)[ix["I"]]
    Wn,sn=gated(W,pD+pR_); net=propagate(Wn,pD+pR_)[ix["I"]]
    print(f"{nome:44s} carga s/ resp={sd['S'][0]:.2f} ({'aberto' if sd['S'][1] else 'fechado'}) | c/ resp={sn['S'][0]:.2f} ({'aberto' if sn['S'][1] else 'fechado'}) | piora I={worse:+.3f} liquido I={net:+.3f}")
base=[("P1","S",.3,"neg"),("P2","S",.3,"neg"),("S","I",.8,"neg")]
run("1. só P1 a 100% (0,3 < 0,4)",base+[("R","P1",.5,"neg")],1,0,0)
run("2. P1+P2 a 100% (0,3+0,3 = 0,6 > 0,4)",base+[("R","P1",.5,"neg")],1,1,0)
run("3. P1+P2 + R→P1 peso 0,5",base+[("R","P1",.5,"neg")],1,1,1)
run("4. P1+P2 + R→P1 peso 0,8",base+[("R","P1",.8,"neg")],1,1,1)
run("5. P1+P2 a 70% (0,42 > 0,4)",base+[("R","P1",.8,"neg")],.7,.7,0)
run("6. P1+P2 a 60% (0,36 < 0,4)",base+[("R","P1",.8,"neg")],.6,.6,0)
