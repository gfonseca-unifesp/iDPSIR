# D (growth_rate g) -> P (w=0.5). Contribuicao que chega em P a cada janela = w_ef(t) * x_D(t)
g=0.10; w=0.5; T=8
def run(model, push):
    xD=0.0; out=[]
    for t in range(1,T+1):
        p = 1.0 if (push=="permanent" or (push=="impulse" and t==1)) else 0.0
        if model=="atual":        # x_D(t+1)=x_D+g*x_D+p ; aresta fixa
            xD = xD + g*xD + p; wef = w
        elif model=="aresta":     # sem termo g*x no no; peso da aresta cresce (1+g)^(t-1)
            xD = xD + p; wef = w*(1+g)**(t-1)
        elif model=="ambos":      # dupla contagem
            xD = xD + g*xD + p; wef = w*(1+g)**(t-1)
        elif model=="tendencia":  # D ganha trajetoria exogena propria: nivel = (1+g)^t - 1 + push acumulado
            xD = ((1+g)**t - 1) + (t if push=="permanent" else (1 if push=="impulse" else 0)); wef = w
        out.append(wef*xD)
    return out
for push in ("impulse","permanent","none"):
    print(f"\n push em D = {push}")
    for m in ("atual","aresta","ambos","tendencia"):
        o=run(m,push); r=[f"{o[i]/o[i-1]:.2f}" if o[i-1] else "-" for i in range(1,T)]
        print(f"  {m:10s} contrib. em P: "+" ".join(f"{v:5.2f}" for v in o)+"   razao/janela: "+" ".join(r))
