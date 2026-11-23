#set package repository ----
options(repos = c(CRAN = "https://packagemanager.posit.co/cran/2026-11-07"))

#load packages ----
pacman::p_load(readr, dplyr, janitor, fs)

#define cutoff ----
#cutoff by approval year, not by observation year
#snapshot is unique and corresponds to 2026
year_corte <- 2022L
year_snapshot <- 2026L

#read and select data ----
procesos_usados <- readr::read_csv("Data/Source-Data/procesos-adquisiciones-psd.csv", show_col_types = FALSE) %>%
  janitor::clean_names() %>%
  dplyr::select(
    numero_prestamo,
    nombre_operacion,
    identificador_proceso,
    nombre_adquisicion,
    categoria_proceso,
    monto_presupuestado_proceso_adquisicion,
    estado_proceso
  )

planes_usados <- readr::read_csv("Data/Source-Data/planes-adquisiciones-psd.csv", show_col_types = FALSE) %>%
  janitor::clean_names() %>%
  dplyr::select(
    numero_prestamo,
    monto_presupuestado_pga_pa
  )

operaciones_usadas <- readr::read_csv("Data/Source-Data/operaciones_indicadores_producto_efecto.csv", show_col_types = FALSE) %>%
  janitor::clean_names() %>%
  dplyr::select(
    linea_credito_no,
    fecha_aprobacion,
    monto_aprobado,
    pais,
    sector_ibcie
  )

#clean processes ----
procesos_clean <- procesos_usados %>%
  dplyr::mutate(
    monto_presupuestado_proceso_adquisicion = as.numeric(monto_presupuestado_proceso_adquisicion),
    estado3 = dplyr::case_when(
      estado_proceso %in% c("Adjudicado", "Contratado", "Contrato Terminado") ~ "ejecutado",
      estado_proceso %in% c("Previsto", "En Curso", "En Evaluación", "Con Lista Corta", "Expresión de Interes en Curso") ~ "pendiente",
      estado_proceso %in% c("Fracasado", "Desierto") ~ "fracasado_desierto",
      TRUE ~ "otro"
    )
  )

dplyr::glimpse(procesos_clean)

#clean and aggregate plans ----
#one loan can have several plan rows by executing agency
planes_clean <- planes_usados %>%
  dplyr::mutate(
    monto_presupuestado_pga_pa = as.numeric(monto_presupuestado_pga_pa)
  ) %>%
  dplyr::group_by(numero_prestamo) %>%
  dplyr::summarise(
    monto_presupuestado_pga_pa = sum(monto_presupuestado_pga_pa, na.rm = TRUE),
    .groups = "drop"
  )

#clean and aggregate operations by credit line ----
#one credit line can have several operations or increments
operaciones_linea <- operaciones_usadas %>%
  dplyr::mutate(
    fecha_aprobacion = as.Date(fecha_aprobacion),
    monto_aprobado = as.numeric(monto_aprobado)
  ) %>%
  dplyr::arrange(linea_credito_no, fecha_aprobacion) %>%
  dplyr::group_by(linea_credito_no) %>%
  dplyr::summarise(
    fecha_aprobacion = dplyr::first(fecha_aprobacion, na_rm = TRUE),
    monto_aprobado = sum(monto_aprobado, na.rm = TRUE),
    pais = dplyr::first(pais, na_rm = TRUE),
    sector_ibcie = dplyr::first(sector_ibcie, na_rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    year_aprobacion = as.integer(format(fecha_aprobacion, "%Y")),
    edad = year_snapshot - year_aprobacion
  )

#join processes with plans and operations ----
#procurement key is numero_prestamo and operations key is linea_credito_no
snapshot_full <- procesos_clean %>%
  dplyr::left_join(planes_clean, by = "numero_prestamo") %>%
  dplyr::left_join(operaciones_linea, by = c("numero_prestamo" = "linea_credito_no")) %>%
  dplyr::add_count(numero_prestamo, name = "n_procesos") %>%
  dplyr::mutate(
    match_operacion = !is.na(year_aprobacion),
    muestra_transversal = !is.na(year_aprobacion) & year_aprobacion <= year_corte,
    log_monto_proceso = log1p(monto_presupuestado_proceso_adquisicion),
    share_plan = monto_presupuestado_proceso_adquisicion / dplyr::na_if(monto_presupuestado_pga_pa, 0),
    plan_sobre_aprobado = monto_presupuestado_pga_pa / dplyr::na_if(monto_aprobado, 0),
    log_monto_aprobado = log1p(monto_aprobado)
  )

#keep model variables and reporting variables ----
variables_modelo <- c(
  "estado3",
  "categoria_proceso",
  "log_monto_proceso",
  "share_plan",
  "log_monto_aprobado",
  "plan_sobre_aprobado",
  "n_procesos",
  "edad",
  "pais",
  "sector_ibcie"
)

variables_corte <- c(
  "numero_prestamo",
  "identificador_proceso",
  "monto_presupuestado_proceso_adquisicion",
  variables_modelo
)

variables_snapshot <- c(
  "numero_prestamo",
  "nombre_operacion",
  "identificador_proceso",
  "nombre_adquisicion",
  "categoria_proceso",
  "monto_presupuestado_proceso_adquisicion",
  "estado_proceso",
  "estado3",
  "monto_presupuestado_pga_pa",
  "monto_aprobado",
  "pais",
  "sector_ibcie",
  "year_aprobacion",
  "edad",
  "n_procesos",
  "log_monto_proceso",
  "share_plan",
  "plan_sobre_aprobado",
  "log_monto_aprobado"
)

snapshot <- snapshot_full %>%
  dplyr::select(dplyr::all_of(variables_snapshot))

#define cross-section ----
corte_transversal <- snapshot_full %>%
  dplyr::filter(muestra_transversal) %>%
  dplyr::select(dplyr::all_of(variables_corte))

#save csv ----
fs::dir_create("Data/csv")

readr::write_csv(snapshot, "Data/csv/snapshot.csv")
readr::write_csv(corte_transversal, "Data/csv/corte_transversal.csv")

