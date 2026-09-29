exec(open("persistencia.py").read().split("chain=[")[0])
chain=[("P","E",1,"neg"),("E","I",1,"neg"),("R","P",1,"neg")]
for sr in ({"E":.3},{"P":.3,"E":.3,"I":.3}):
  for mR in ("impulse","permanent"):
    o,lam=sim(chain,"permanent",mR,True,30,sr)
    print(sr,mR," | ".join(f"t{t}: I={s:+.2f} base={b:.1f} {verd(b,s)}" for t,b,s,r,p in o if t in (3,5,10,20,30)))
