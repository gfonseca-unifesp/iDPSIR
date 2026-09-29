exec(open("teste_psir.py").read().split("base=[")[0])
def propagate(W,p,c=.5):
    r=rho(W); lam = 1.0 if r<1e-12 else min(1.0, c/r)   # proposta: lambda = min(1, c/rho)
    return np.linalg.solve(np.eye(4)-lam*W,p)-p, lam, r
base=[("P","E",1,"neg"),("E","I",1,"neg"),("R","P",1,"neg")]
casos={"A":base,"B (I→R 1)":base+[("I","R",1,"pos")],"C (I→R 0,001)":base+[("I","R",0.001,"pos")],"D pesos 3":[(f,t,3,s) for f,t,_,s in base]}
for c in (0.5,0.9):
  print("c =",c)
  for k,e in casos.items():
    r=suff(e,c=c); print(f"  {k}: lam={r['lam']:.3g} piora={r['piora']:.4g} mitig={r['mitig']:.4g} liquido={r['liquido']:.3g} forca={r['forca_necessaria']:.3g}")
