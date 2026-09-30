# =====================================================
# SCENARIO CHARTS (trajectory / edge sensitivity)
# =====================================================
#
# Pure base-R plotting functions, no Shiny/UI dependency - shared between
# mod_responses.R's on-screen renderPlot()/downloadHandler()s and
# report.R's embedded report images, so the exact same drawing code
# produces the on-screen chart, the downloaded file, and the report
# figure, instead of three implementations that could drift apart.


# =====================================================
# TEMPORAL LINE CHART (Revisao 1: guia externo sobre o relatorio como
# material suplementar, CLAUDE.md) - substitui draw_temporal_storyboard()
# acima como a figura temporal principal. draw_temporal_storyboard() fica
# definida (superseded-code-stays-on-disk, mesmo padrao ja usado em todo o
# projeto - ex. press_perturbation() em R/loop_analysis.R), so' deixa de
# ser chamada por mod_responses.R/report.R.
#
# Motivo real da troca (nao so' preferencia estetica): o storyboard de
# paineis-de-rede convida uma leitura errada especifica - o leitor ve o
# ponto do cenario "abaixo" do baseline (mais azul) e conclui que o
# Impacto foi neutralizado, quando neutralizacao e' definida em relacao a
# ZERO, nao ao baseline (ver format_temporal_table()/temporal_stability_note()
# em R/temporal.R, e "Reading the Verdict" em docs/tutorial.html). Um
# grafico de linha por Impacto - baseline tracejado vs. net solido, com a
# faixa "net <= 0" sombreada como a zona neutralizada - remove essa
# ambiguidade sem exigir uma segunda leitura.
#
# Regra de ouro deste arquivo: a cor de cada ponto do "net" vem
# DIRETAMENTE da coluna `verdict` que format_temporal_table() ja calculou
# (idpsir_verdict_palette[verdict]) - nunca um novo teste de sinal
# recomputado aqui. Isso e' o que garante que a figura nunca pode discordar
# da tabela temporal (mesmo dado, mesma cor, em dois lugares).
# =====================================================

# Strings de veredito exatamente como format_temporal_table() (R/temporal.R)
# as emite - se esse vocabulario mudar la, precisa mudar aqui tambem (dai o
# teste de contrato em tests/testthat/test-temporal.R que confere que todo
# veredito gerado bate com uma chave desta paleta).
idpsir_verdict_palette <- c(
  "Improved beyond neutral" = "#1b8a3a", # verde - net <= 0, alem do neutro
  "Neutralized"             = "#1b8a3a", # verde - segurou no neutro
  "Neutralized (relative)"  = "#8fd19e", # verde claro - dentro da tolerancia relativa (Revisao 2, A3)
  "Partial"                 = "#e0a100", # ambar - ajudou, ainda positivo
  "Failure/worsened"        = "#c0392b", # vermelho - tao ruim ou pior que o baseline
  "Not affected"            = "#bdbdbd", # cinza - a pressao nao alcanca o Impacto (Revisao 2, 2.1)
  "\u2014"                  = "#bdbdbd"  # janela 0, sem veredito
)

# @param temporal_df saida de format_temporal_table(): colunas id/node/
#   window/baseline_impact/net_impact/verdict (uma linha por Impacto x
#   janela). `id` nao e' usado pro desenho (so' `node`, o rotulo).
# @param reinforcing_warning logical - reaproveita temporal_result$stability's
#   proprio sinalizador (via temporal_stability_note()), nunca recalculado
#   aqui.
# @param by_scenario mantido por paridade de assinatura com o guia externo,
#   mas nenhum chamador deste projeto o usa: cada cenario ja ganha sua
#   propria figura/subsecao em todo o resto do relatorio (suficiencia,
#   reach, confianca) - combinar cenario x Impacto numa unica grade quebraria
#   esse padrao ja estabelecido, entao este parametro fica sem efeito por
#   enquanto (reservado, nao implementado).
# @param neutralized_at janela em que a simulacao "ate neutralizar" parou
#   (Revisao 2, A2) - desenhada como linha vertical; NA = nenhuma.
plot_temporal_storyboard <- function(temporal_df, reinforcing_warning = FALSE, by_scenario = FALSE, neutralized_at = NA) {
  stopifnot(all(c("node", "window", "baseline_impact", "net_impact", "verdict") %in% names(temporal_df)))

  if (nrow(temporal_df) == 0) {
    plot.new()
    text(0.5, 0.5, "No Impact factors in this network yet.")
    return(invisible())
  }

  # unique() preserva a ordem de emissao de format_temporal_table() (ordem
  # dos nos Impact no grafo), nao ordem alfabetica - mesmo padrao de
  # ordenacao ja usado pelas demais tabelas deste app.
  impacts <- unique(temporal_df$node)
  n_panels <- length(impacts)

  ncol_grid <- ceiling(sqrt(n_panels))
  nrow_grid <- ceiling(n_panels / ncol_grid)
  n_cells <- nrow_grid * ncol_grid
  panel_ids <- c(seq_len(n_panels), rep(0L, n_cells - n_panels))
  grid_mat <- matrix(panel_ids, nrow = nrow_grid, ncol = ncol_grid, byrow = TRUE)
  legend_id <- n_panels + 1L
  # Linha extra no rodape, ocupando todas as colunas, pra legenda
  # compartilhada (mesma tecnica de "celula com o mesmo numero = uma
  # regiao so'" ja usada por draw_temporal_storyboard() acima, so' que
  # como linha em vez de coluna).
  grid_mat <- rbind(grid_mat, rep(legend_id, ncol_grid))

  old_par <- graphics::par(mar = c(3.2, 3.5, 2, 1))
  on.exit(graphics::par(old_par))
  legend_height <- max(0.22, 0.55 / (nrow_grid + 1))
  graphics::layout(grid_mat, heights = c(rep(1, nrow_grid), legend_height))

  for (impact in impacts) {
    sub <- temporal_df[temporal_df$node == impact, ]
    sub <- sub[order(sub$window), ]

    # 0 sempre entra no calculo do range - garante que a "zona
    # neutralizada" (y <= 0) sempre tem pelo menos uma fatia visivel do
    # painel pra sombrear, mesmo num Impacto que nunca chega perto de
    # zero.
    y_range <- range(c(sub$baseline_impact, sub$net_impact, 0), na.rm = TRUE)
    pad <- diff(y_range) * 0.08
    if (!is.finite(pad) || pad == 0) pad <- max(abs(y_range), 1) * 0.1
    ylim <- c(y_range[1] - pad, y_range[2] + pad)

    graphics::plot(
      sub$window, sub$net_impact, type = "n",
      xlab = "window", ylab = "value  (+ worse . - improved)",
      ylim = ylim, main = impact, cex.main = 0.95
    )

    # Zona neutralizada (net <= 0) sombreada + linha de referencia em
    # zero - as duas ancoras de leitura que o storyboard antigo nao
    # deixava explicitas (ver o motivo real acima).
    usr <- graphics::par("usr")
    graphics::rect(usr[1], usr[3], usr[2], min(0, usr[4]), col = "#e7f4ea", border = NA)
    graphics::box() # rect() acima desenha por cima da borda do plot; redesenha
    graphics::abline(h = 0, col = "#8a919b", lwd = 1)
    if (length(neutralized_at) == 1 && !is.na(neutralized_at)) {
      graphics::abline(v = neutralized_at, col = "#2e7d32", lty = 3, lwd = 1.5)
    }

    # Baseline (so' pressao): tracejado cinza, pontos abertos.
    graphics::lines(sub$window, sub$baseline_impact, lty = 2, col = "#6b7280", lwd = 1.5)
    graphics::points(sub$window, sub$baseline_impact, pch = 21, bg = "white", col = "#6b7280", cex = 1.1)

    # Net (pressao + resposta): solido, pontos coloridos pelo veredito ja
    # calculado - nunca um novo teste de sinal aqui.
    graphics::lines(sub$window, sub$net_impact, col = "#3a3f47", lwd = 1.5)
    point_colors <- unname(idpsir_verdict_palette[sub$verdict])
    graphics::points(sub$window, sub$net_impact, pch = 21, bg = point_colors, col = "#222222", cex = 1.4)
  }

  draw_temporal_legend(reinforcing_warning)
}

# Legenda compartilhada da figura: chave de cor (baseline + os 3 grupos de
# veredito por cor - "Neutralized"/"Improved beyond neutral" combinados
# num unico item, ja que os dois compartilham a mesma cor verde) mais,
# quando a rede tem um loop de reforco que a auto-regulacao configurada
# nao neutraliza (reinforcing_warning = TRUE), a mesma frase de
# temporal_stability_note() (R/temporal.R) como legenda em vermelho -
# nunca reescrita aqui, so' repassada por quem chama esta funcao.
draw_temporal_legend <- function(reinforcing_warning = FALSE) {
  graphics::par(mar = c(0.2, 1, 0.2, 1))
  graphics::plot.new()
  graphics::legend(
    "left", horiz = TRUE, bty = "n", cex = 0.85, x.intersp = 0.6,
    legend = c(
      "Baseline (pressure only)",
      "Net: neutralized / improved (≤ 0)",
      "Net: within tolerance of baseline",
      "Net: partial (> 0, better than baseline)",
      "Net: failure/worsened (≥ baseline)"
    ),
    pch = 21,
    pt.bg = c("white", idpsir_verdict_palette[["Neutralized"]], idpsir_verdict_palette[["Neutralized (relative)"]],
              idpsir_verdict_palette[["Partial"]], idpsir_verdict_palette[["Failure/worsened"]]),
    col = c("#6b7280", "#222222", "#222222", "#222222", "#222222"),
    pt.cex = 1.3
  )

  if (isTRUE(reinforcing_warning)) {
    graphics::mtext(
      "Reinforcing loop stronger than self-regulation: the baseline grows without bound - read direction, not magnitude.",
      side = 1, line = -1, cex = 0.72, font = 2, col = "#c0392b"
    )
  }
}

# Renders `draw_fn()` to a PNG/SVG file at `path` - used both by
# downloadHandler()s (which write straight to the download's `file`
# path) and by report.R's embedded <img> (rendered to a tempfile, then
# base64-encoded via jsonlite - already a dependency - instead of
# pulling in a new package like base64enc just for this).
render_plot_png <- function(draw_fn, path, width = 800, height = 450) {
  grDevices::png(path, width = width, height = height, res = 96)
  on.exit(grDevices::dev.off())
  draw_fn()
}

render_plot_svg <- function(draw_fn, path, width = 8.33, height = 4.69) {
  grDevices::svg(path, width = width, height = height)
  on.exit(grDevices::dev.off())
  draw_fn()
}

# Shared by report.R for both charts - render to a tempfile, read back as
# a base64 data URI, clean up. Kept here (not duplicated in report.R)
# since it's presentation plumbing, not report-assembly logic.
plot_to_data_uri <- function(draw_fn, width = 800, height = 450) {
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp))
  render_plot_png(draw_fn, tmp, width = width, height = height)
  paste0("data:image/png;base64,", jsonlite::base64_enc(readBin(tmp, "raw", file.info(tmp)$size)))
}

# Revisao 2, item B7: horizontal bars of each Impact's relevance, with a
# black marker at its priority (figure 7.4 of the relevance specification).
# Impacts the pressure does not worsen ("Not affected") are left out.
draw_prioritization_plot <- function(prio_df) {
  df <- prio_df[prio_df$affected, , drop = FALSE]
  if (nrow(df) == 0) {
    plot.new()
    text(0.5, 0.5, "No Impact is worsened by this pressure scenario.")
    return(invisible())
  }
  df <- df[order(df$relevance), , drop = FALSE]
  old_par <- graphics::par(mar = c(4, max(8, max(nchar(df$node)) * 0.55), 1.5, 1))
  on.exit(graphics::par(old_par))
  y <- graphics::barplot(
    df$relevance, names.arg = df$node, horiz = TRUE, las = 1, xlim = c(0, 1),
    col = "#c9d7e8", border = NA, xlab = "relevance (bar) and priority (marker)", cex.names = 0.85
  )
  graphics::points(df$priority, y, pch = 23, bg = "#1f2937", col = "#1f2937", cex = 1.3)
  graphics::legend("bottomright", bty = "n", cex = 0.8, pch = c(15, 23), col = c("#c9d7e8", "#1f2937"),
                   pt.bg = c("#c9d7e8", "#1f2937"), legend = c("relevance = v x D x reliability", "priority = relevance x gap"))
}
