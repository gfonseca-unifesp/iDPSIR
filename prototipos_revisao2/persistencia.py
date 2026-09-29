# Porta de temporal.R: x(t+1) = x + (lam*W) x + p ; W inclui -self_regulation na diagonal; lam=min(1,0.9/rho)
import numpy as np
N=["P","E","I","R"]; ix={n:i for i,n in enumerate(N)}
def W_of(edges, sr={}):
    W=np.zeros((4,4))
    for f,t,w,s in edges: W[ix[t],ix[f]]+=(-1 if s=="neg" else 1)*w
    for n,v in sr.items(): W[ix[n],ix[n]]-=v
    return W
def rho(W): return max(abs(np.linalg.eigvals(W))) if np.any(W) else 0
def sim(edges,modeD="permanent",modeR="impulse",pR_on=True,T=20,sr={}):
    W=W_of(edges,sr); r=rho(W); lam=1 if r==0 else min(1,.9/r); W=lam*W
    pD=np.eye(4)[ix["P"]]; pR=np.eye(4)[ix["R"]]*(1 if pR_on else 0)
    xb=np.zeros(4); xs=np.zeros(4); out=[]
    for t in range(1,T+1):
        d=pD if (modeD=="permanent" or t==1) else 0*pD
        q=pR if (modeR=="permanent" or t==1) else 0*pR
        xb=xb+W@xb+d; xs=xs+W@xs+d+q
        out.append((t,xb[ix["I"]],xs[ix["I"]],xs[ix["R"]],xs[ix["P"]]))
    return out,lam
def verd(b,s): return "Neutr" if abs(s)<=1e-9 else ("Melhor" if s<0 else ("Falha" if s>=b-1e-9 else "Parcial"))
chain=[("P","E",1,"neg"),("E","I",1,"neg"),("R","P",1,"neg")]
fb=lambda w:[("I","R",w,"pos")]
casos=[
 ("1 impulso, sem I→R",chain,"impulse",True,{}),
 ("2 permanente, sem I→R",chain,"permanent",True,{}),
 ("3 impulso, R com autorregulação 0,5",chain,"impulse",True,{"R":.5}),
 ("4 sem disparo, só I→R peso 1",chain+fb(1),"impulse",False,{}),
 ("5 impulso + I→R peso 1",chain+fb(1),"impulse",True,{}),
 ("6 impulso + I→R peso 0,3",chain+fb(.3),"impulse",True,{}),
 ("7 impulso + I→R peso 1, E com autorreg. 0,3",chain+fb(1),"impulse",True,{"E":.3}),
 ("8 pressão impulso, resposta impulso, sem I→R",chain,"impulse",True,{}),
]
for nome,e,mR,on,sr in casos:
    mD="impulse" if nome.startswith("8") else "permanent"
    o,lam=sim(e,mD,mR,on,20,sr)
    sel=[1,2,3,4,5,6,8,10,15,20]
    print(f"{nome} (lam={lam:.2f})")
    print("   "+" | ".join(f"t{t}: I={s:+.2f} (base {b:.1f}) R={r:.2f} {verd(b,s)}" for t,b,s,r,p in o if t in sel))

print("\n== Protótipo: modo 'até neutralizar' (R recebe +1 na janela só se I > 0 na janela anterior) ==")
for sr in ({}, {"R":0.5}):
  W=W_of(chain,sr); pD=np.eye(4)[ix["P"]]; pR=np.eye(4)[ix["R"]]
  xs=np.zeros(4); xb=np.zeros(4); row=[]
  for t in range(1,21):
      q=pR if (t==1 or xs[ix["I"]]>1e-9) else 0*pR
      xb=xb+W@xb+pD; xs=xs+W@xs+pD+q
      if t in (1,3,5,8,10,12,15,20): row.append(f"t{t}: I={xs[ix['I']]:+.1f} R={xs[ix['R']]:.0f}")
  print(" autorreg R",sr.get("R",0)," | ".join(row))
