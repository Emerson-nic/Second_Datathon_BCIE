rm(list = ls())

#set package repository ----
options(repos = c(CRAN = "https://packagemanager.posit.co/cran/2026-11-07"))

#load packages ----
pacman::p_load(readr, 
               dplyr, 
               sandwich, 
               lmtest)

#read cross-section ----

datos <- readr::read_csv("Data/csv/corte_transversal.csv", show_col_types = FALSE) %>%
  dplyr::mutate(
    categoria_proceso = factor(categoria_proceso),
    pendiente = as.integer(estado3 == "pendiente")
  )

#logit model  ----

modelo <- stats::glm(
  pendiente ~ categoria_proceso + log_monto_proceso + share_plan +
    log_monto_aprobado + plan_sobre_aprobado + n_procesos + edad,
  data = datos,
  family = stats::binomial
)

summary(modelo)
exp(stats::coef(modelo)) 

#standard errors grouped by operation ----
lmtest::coeftest(modelo, vcov = sandwich::vcovCL(modelo, cluster = ~numero_prestamo))

#probability by process
datos$p_pend <- stats::predict(modelo, type = "response")

#danger zone ----

operaciones <- datos %>%
  dplyr::group_by(numero_prestamo) %>%
  dplyr::summarise(
    n_procesos = dplyr::n(),
    edad = dplyr::first(edad),
    monto_total = sum(monto_presupuestado_proceso_adquisicion),
    monto_pendiente = sum(monto_presupuestado_proceso_adquisicion * p_pend),
    share_pendiente = monto_pendiente / monto_total,
    share_obs = sum(monto_presupuestado_proceso_adquisicion * pendiente) / monto_total,
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    #fixed thresholds
    semaforo_abs = dplyr::case_when(
      share_pendiente >= 0.60 ~ "Rojo",
      share_pendiente >= 0.40 & edad >= 6 ~ "Rojo",
      share_pendiente >= 0.30 ~ "Amarillo",
      TRUE ~ "Verde"
    ),
    #relative thresholds, share_pendiente tertiles
    tercil = dplyr::ntile(share_pendiente, 3),
    semaforo = dplyr::case_when(
      tercil == 3 ~ "Rojo",
      tercil == 2 ~ "Amarillo",
      TRUE ~ "Verde"
    )
  ) %>%
  dplyr::select(-tercil)

table(operaciones$semaforo_abs, operaciones$semaforo)

operaciones %>%
  dplyr::group_by(semaforo) %>%
  dplyr::summarise(
    n = dplyr::n(),
    share_min = min(share_pendiente),
    share_max = max(share_pendiente),
    monto_pendiente = sum(monto_pendiente),
    .groups = "drop"
  )

#test

operaciones %>%
  dplyr::summarise(
    MAE = mean(abs(share_pendiente - share_obs)),
    RMSE = sqrt(mean((share_pendiente - share_obs)^2))
  )

#leave-one-operation-out

ops <- unique(datos$numero_prestamo)

datos$p_looo <- NA_real_
for (o in ops) {
  entren <- datos[datos$numero_prestamo != o, ]
  prueba <- datos$numero_prestamo == o
  m_o <- stats::glm(stats::formula(modelo), data = entren, family = stats::binomial)
  datos$p_looo[prueba] <- stats::predict(m_o, newdata = datos[prueba, ], type = "response")
}

evaluar <- function(p) {
  datos %>%
    dplyr::mutate(p_ = p) %>%
    dplyr::group_by(numero_prestamo) %>%
    dplyr::summarise(
      pred = sum(monto_presupuestado_proceso_adquisicion * p_) /
        sum(monto_presupuestado_proceso_adquisicion),
      obs = sum(monto_presupuestado_proceso_adquisicion * pendiente) /
        sum(monto_presupuestado_proceso_adquisicion),
      .groups = "drop"
    ) %>%
    dplyr::summarise(
      MAE = mean(abs(pred - obs)),
      RMSE = sqrt(mean((pred - obs)^2)),
      cor = stats::cor(pred, obs)
    )
}

evaluar(datos$p_looo)                                  
evaluar(rep(mean(datos$pendiente), nrow(datos)))  

#calibration ----

#by process: LOOO probability deciles
calib_proceso <- datos %>%
  dplyr::mutate(decil = dplyr::ntile(p_looo, 10)) %>%
  dplyr::group_by(decil) %>%
  dplyr::summarise(
    p_media = mean(p_looo),
    obs_media = mean(pendiente),
    n = dplyr::n(),
    .groups = "drop"
  )

calib_proceso

#per trade: forecast vs observed
calib_operacion <- datos %>%
  dplyr::group_by(numero_prestamo) %>%
  dplyr::summarise(
    pred = sum(monto_presupuestado_proceso_adquisicion * p_looo) /
      sum(monto_presupuestado_proceso_adquisicion),
    obs = sum(monto_presupuestado_proceso_adquisicion * pendiente) /
      sum(monto_presupuestado_proceso_adquisicion),
    .groups = "drop"
  )

#outstanding amount bias 
datos %>%
  dplyr::summarise(
    monto_pend_obs = sum(monto_presupuestado_proceso_adquisicion * pendiente),
    monto_pend_pred = sum(monto_presupuestado_proceso_adquisicion * p_looo),
    ratio = monto_pend_pred / monto_pend_obs
  )

#sensibility test ----

sensibilidad <- function(d, etiqueta) {
  m <- stats::glm(stats::formula(modelo), data = d, family = stats::binomial)
  tibble::tibble(
    muestra = etiqueta,
    n_ops = dplyr::n_distinct(d$numero_prestamo),
    n_proc = nrow(d),
    b_log_monto_proceso = stats::coef(m)[["log_monto_proceso"]],
    b_plan_sobre_aprobado = stats::coef(m)[["plan_sobre_aprobado"]],
    b_edad = stats::coef(m)[["edad"]]
  )
}

dplyr::bind_rows(
  sensibilidad(datos, "Principal (≤2022)"),
  sensibilidad(dplyr::filter(datos, edad >= 7), "≤2019"),
  sensibilidad(dplyr::filter(datos, !numero_prestamo %in% c("2245", "2317")), "Sin ops. 2245 y 2317"),
  sensibilidad(dplyr::filter(datos, estado3 != "fracasado_desierto"), "Sin fracasados")
)

