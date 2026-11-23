rm(list = ls())

#set package repository ----
options(repos = c(CRAN = "https://packagemanager.posit.co/cran/2026-11-07"))

#load packages ----
pacman::p_load(readr, dplyr, tidyr, ggplot2, scales, ggrepel, patchwork, fs)

#read outputs ----
datos <- readr::read_csv("Data/csv/corte_transversal.csv", show_col_types = FALSE)
operaciones <- readr::read_csv("Data/csv/operaciones_semaforo.csv", show_col_types = FALSE)
coeficientes <- readr::read_csv("Data/csv/modelo_coeficientes.csv", show_col_types = FALSE)
predicciones <- readr::read_csv("Data/csv/predicciones_proceso.csv", show_col_types = FALSE)
modelo_ajuste <- readr::read_csv("Data/csv/modelo_ajuste.csv", show_col_types = FALSE)

#common objects ----
paleta_estado <- c(ejecutado = "#1F4E79", pendiente = "#8FA9C4", fracasado_desierto = "#7A7A7A")
paleta_semaforo <- c(Verde = "#2E7D32", Amarillo = "#F9A825", Rojo = "#C62828")
tema <- ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(legend.position = "bottom")

#titles, subtitles and source are intentionally omitted 

#figure 01: state totals ----
#title: La brecha pendiente concentra una cuarta parte del monto
estado <- datos %>%
  dplyr::group_by(estado3) %>%
  dplyr::summarise(
    procesos = dplyr::n(),
    monto = sum(monto_presupuestado_proceso_adquisicion),
    .groups = "drop"
  ) %>%
  tidyr::pivot_longer(c(procesos, monto), names_to = "medida", values_to = "valor")

fig01 <- ggplot2::ggplot(
  estado,
  ggplot2::aes(x = "Muestra", y = valor, fill = estado3)
) +
  ggplot2::geom_col(position = "fill") +
  ggplot2::facet_wrap(~medida, scales = "free_y") +
  ggplot2::scale_fill_manual(values = paleta_estado) +
  ggplot2::scale_y_continuous(labels = scales::percent) +
  ggplot2::labs(x = NULL, y = "Proporcion", fill = "Estado") +
  tema

ggplot2::ggsave("Plots/fig01_estado_conteo_monto.pdf", fig01,
                device = grDevices::cairo_pdf, width = 7, height = 4.5)

#figure 02: observed gap by country and category ----
#title: La brecha observada varia por pais y categoria
brecha_pais <- datos %>%
  dplyr::group_by(grupo = pais) %>%
  dplyr::summarise(
    brecha = sum(monto_presupuestado_proceso_adquisicion[estado3 == "pendiente"]) /
      sum(monto_presupuestado_proceso_adquisicion),
    n_unidades = dplyr::n_distinct(numero_prestamo),
    .groups = "drop"
  ) %>%
  dplyr::mutate(etiqueta = paste0(grupo, " (n=", n_unidades, ")"), tipo = "Pais")

brecha_categoria <- datos %>%
  dplyr::group_by(grupo = categoria_proceso) %>%
  dplyr::summarise(
    brecha = sum(monto_presupuestado_proceso_adquisicion[estado3 == "pendiente"]) /
      sum(monto_presupuestado_proceso_adquisicion),
    n_unidades = dplyr::n(),
    .groups = "drop"
  ) %>%
  dplyr::mutate(etiqueta = paste0(grupo, " (n=", n_unidades, ")"), tipo = "Categoria")

brecha <- dplyr::bind_rows(brecha_pais, brecha_categoria) %>%
  dplyr::group_by(tipo) %>%
  dplyr::arrange(brecha, .by_group = TRUE) %>%
  dplyr::mutate(etiqueta = factor(etiqueta, levels = etiqueta)) %>%
  dplyr::ungroup()

fig02 <- ggplot2::ggplot(brecha, ggplot2::aes(x = brecha, y = etiqueta)) +
  ggplot2::geom_col(fill = "#1F4E79") +
  ggplot2::facet_wrap(~tipo, scales = "free_y") +
  ggplot2::scale_x_continuous(labels = scales::percent) +
  ggplot2::labs(x = "Monto pendiente / monto planificado", y = NULL) +
  tema

ggplot2::ggsave("Plots/fig02_brecha_pais_categoria.pdf", fig02,
                device = grDevices::cairo_pdf, width = 7, height = 4.5)

#figure 03: operation dispersion ----
#title: Diez operaciones concentran la mayor exposicion esperada
top10 <- operaciones %>%
  dplyr::arrange(dplyr::desc(monto_pendiente)) %>%
  dplyr::slice_head(n = 10)

fig03 <- ggplot2::ggplot(
  operaciones,
  ggplot2::aes(x = share_pendiente, y = monto_pendiente, size = edad, color = semaforo)
) +
  ggplot2::geom_point(alpha = .8) +
  ggplot2::geom_vline(xintercept = c(.3, .6), linetype = "dashed") +
  ggrepel::geom_text_repel(
    data = top10,
    ggplot2::aes(label = numero_prestamo),
    size = 3,
    show.legend = FALSE
  ) +
  ggplot2::scale_x_continuous(labels = scales::percent) +
  ggplot2::scale_y_log10(labels = scales::label_dollar()) +
  ggplot2::scale_color_manual(values = paleta_semaforo) +
  ggplot2::labs(
    x = "Participacion pendiente esperada",
    y = "Monto pendiente esperado, USD",
    size = "Edad",
    color = "Semaforo"
  ) +
  tema

ggplot2::ggsave("Plots/fig03_dispersion_share_monto.pdf", fig03,
                device = grDevices::cairo_pdf, width = 7, height = 4.5)

#figure 04: top ten ----
#title: Top 10 de operaciones por monto pendiente esperado
top10 <- top10 %>%
  dplyr::mutate(
    etiqueta = paste0(numero_prestamo, " - ", pais),
    etiqueta = factor(etiqueta, levels = rev(etiqueta))
  )

fig04 <- ggplot2::ggplot(
  top10,
  ggplot2::aes(x = monto_pendiente, y = etiqueta)
) +
  ggplot2::geom_col(fill = "#C62828") +
  ggplot2::scale_x_continuous(labels = scales::label_dollar()) +
  ggplot2::labs(x = "Monto pendiente esperado, USD", y = NULL) +
  tema

ggplot2::ggsave("Plots/fig04_top10.pdf", fig04,
                device = grDevices::cairo_pdf, width = 7, height = 4.5)

#figure 05: risk matrix ----
#title: El riesgo combina edad de la operacion y brecha esperada
matriz <- operaciones %>%
  dplyr::mutate(
    banda_edad = dplyr::case_when(
      edad < 6 ~ "4-5 años",
      edad < 10 ~ "6-9 años",
      TRUE ~ "10+ años"
    ),
    banda_share = dplyr::case_when(
      share_pendiente < .3 ~ "Verde: <30%",
      share_pendiente < .6 ~ "Amarillo: 30-60%",
      TRUE ~ "Rojo: >=60%"
    )
  ) %>%
  dplyr::group_by(banda_edad, banda_share) %>%
  dplyr::summarise(
    n = dplyr::n(),
    monto = sum(monto_pendiente),
    etiqueta = paste0(n, " ops\n", scales::dollar(monto)),
    .groups = "drop"
  )

fig05 <- ggplot2::ggplot(
  matriz,
  ggplot2::aes(x = banda_edad, y = banda_share, label = etiqueta)
) +
  ggplot2::geom_tile(fill = "#F9A825", color = "white") +
  ggplot2::geom_text() +
  ggplot2::labs(x = "Edad de la operacion", y = "Banda de participacion pendiente") +
  tema

ggplot2::ggsave("Plots/fig05_matriz_riesgo.pdf", fig05,
                device = grDevices::cairo_pdf, width = 7, height = 4.5)

#figure 06: odds ratios ----
#title: El monto del proceso se asocia con mayor probabilidad de quedar pendiente
coef_plot <- coeficientes %>%
  dplyr::filter(termino != "(Intercept)") %>%
  dplyr::mutate(
    termino = dplyr::recode(
      termino,
      log_monto_proceso = "Monto del proceso (log1p)",
      share_plan = "Participacion en el plan",
      log_monto_aprobado = "Monto aprobado (log1p)",
      plan_sobre_aprobado = "Plan / aprobado",
      n_procesos = "Numero de procesos",
      edad = "Edad",
      .default = termino
    ),
    termino = factor(termino, levels = rev(termino))
  )

fig06 <- ggplot2::ggplot(coef_plot, ggplot2::aes(x = odds_ratio, y = termino)) +
  ggplot2::geom_vline(xintercept = 1, linetype = "dashed") +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = ic_95_inf, xmax = ic_95_sup),
    orientation = "y",
    width = .2
  ) +
  ggplot2::geom_point() +
  ggplot2::scale_x_log10() +
  ggplot2::labs(x = "Odds ratio e intervalo de confianza del 95%", y = NULL) +
  tema

ggplot2::ggsave("Plots/fig06_odds_ratios.pdf", fig06,
                device = grDevices::cairo_pdf, width = 7, height = 4.5)

#figure 07: calibration ----
#title: La validacion fuera de muestra supera al benchmark constante
calib <- predicciones %>%
  dplyr::mutate(decil = dplyr::ntile(p_looo, 10)) %>%
  dplyr::group_by(decil) %>%
  dplyr::summarise(
    pred = mean(p_looo),
    obs = mean(pendiente),
    .groups = "drop"
  )

fig07a <- ggplot2::ggplot(calib, ggplot2::aes(x = pred, y = obs)) +
  ggplot2::geom_abline(linetype = "dashed") +
  ggplot2::geom_point() +
  ggplot2::geom_line() +
  ggplot2::scale_x_continuous(labels = scales::percent) +
  ggplot2::scale_y_continuous(labels = scales::percent) +
  ggplot2::labs(x = "Prediccion LOOO", y = "Observado") +
  tema

fig07b <- ggplot2::ggplot(operaciones, ggplot2::aes(x = pred_looo, y = obs)) +
  ggplot2::geom_abline(linetype = "dashed") +
  ggplot2::geom_point(color = "#1F4E79") +
  ggplot2::scale_x_continuous(labels = scales::percent) +
  ggplot2::scale_y_continuous(labels = scales::percent) +
  ggplot2::labs(x = "Prediccion LOOO", y = "Observado") +
  tema

fig07 <- fig07a + fig07b

ggplot2::ggsave("Plots/fig07_calibracion.pdf", fig07,
                device = grDevices::cairo_pdf, width = 7, height = 4.5)

#figure 08: sensitivity ----
#title: Los signos de los factores clave se mantienen en tres de cuatro muestras
sens <- modelo_ajuste %>%
  dplyr::filter(metrica == "sensibilidad") %>%
  tidyr::pivot_longer(
    c(b_log_monto_proceso, b_plan_sobre_aprobado, b_edad),
    names_to = "variable",
    values_to = "coeficiente"
  )

fig08 <- ggplot2::ggplot(
  sens,
  ggplot2::aes(x = coeficiente, y = muestra, color = variable)
) +
  ggplot2::geom_vline(xintercept = 0, linetype = "dashed") +
  ggplot2::geom_point(size = 2) +
  ggplot2::facet_wrap(~variable, scales = "free_x") +
  ggplot2::labs(x = "Coeficiente logit", y = NULL, color = "Variable") +
  tema

ggplot2::ggsave("Plots/fig08_sensibilidad.pdf", fig08,
                device = grDevices::cairo_pdf, width = 7, height = 4.5)
