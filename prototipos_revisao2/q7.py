import numpy as np
N=["P1","P2","S","I","R"]; ix={n:i for i,n in enumerate(N)}
E=[("P1","S",.3,-1),("P2","S",.3,-1),("S","I",.8,-1),("R","P1",.8,-1)]
W=np.zeros((5,5))
for f,t,w,s in E: W[ix[t],ix[f]]+=s*w
TH=0.4
def sim(mode,pushP,modeP,pushR,T=6):
    x=np.zeros(5); out=[]
    for t in range(1,T+1):
        p=np.zeros(5)
        if modeP=="permanent" or t==1:
            for n in pushP: p[ix[n]]=1
        if pushR and t==1: p[ix["R"]]=1
        if mode=="carga": L=abs(W[ix["S"],ix["P1"]]*x[ix["P1"]]+W[ix["S"],ix["P2"]]*x[ix["P2"]]+W[ix["S"],ix["R"]]*x[ix["R"]])
        else: L=abs(x[ix["S"]])
        Wg=W.copy()
        if L<TH: Wg[:,ix["S"]]=0
        x=x+Wg@x+p
        out.append(("A" if L>=TH else "f")+f"{x[ix['I']]:+.2f}")
    return " ".join(out)
casos=[("P1 sozinha, permanente",["P1"],"permanent",False),
       ("P1 sozinha, impulso",["P1"],"impulse",False),
       ("P1+P2, impulso",["P1","P2"],"impulse",False),
       ("P1+P2, permanente",["P1","P2"],"permanent",False),
       ("P1+P2 permanente + resposta R->P1",["P1","P2"],"permanent",True)]
for nome,pp,mp,r in casos:
    print(nome)
    for m in ("carga","nivel"): print(f"   {m:6s}", sim(m,pp,mp,r))
