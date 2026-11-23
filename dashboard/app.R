#set package repository ----
options(repos = c(CRAN = "https://packagemanager.posit.co/cran/2026-11-07"))

#load packages ----
pacman::p_load(shiny, plotly, DT, readr, dplyr, ggplot2, scales, jsonlite)

#read data ----
datos <- readr::read_csv("data/corte_transversal.csv", show_col_types = FALSE)
operaciones <- readr::read_csv("data/operaciones_semaforo.csv", show_col_types = FALSE)
coeficientes <- readr::read_csv("data/modelo_coeficientes.csv", show_col_types = FALSE)
predicciones <- readr::read_csv("data/predicciones_proceso.csv", show_col_types = FALSE)

#palette and helpers ----
paleta_estado <- c(ejecutado = "#1F4E79", pendiente = "#8FA9C4", fracasado_desierto = "#7A7A7A")
paleta_semaforo <- c(Verde = "#2E7D32", Amarillo = "#F9A825", Rojo = "#C62828")
tema <- ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(legend.position = "bottom", plot.title = ggplot2::element_text(face = "bold"))

#interface ----
ui <- shiny::navbarPage(
  title = "Planes de adquisiciones del BCIE",
  header = shiny::tags$head(
    shiny::tags$style(shiny::HTML("body { font-family: Arial, sans-serif; } .small-note { color: #555; font-size: 0.9em; } .risk-result { font-size: 1.5em; font-weight: bold; color: #1F4E79; }"))
  ),
  shiny::tabPanel(
    "Resumen",
    shiny::fluidRow(
      shiny::column(3, shiny::wellPanel(shiny::h4("Brecha de monto"), shiny::textOutput("brecha"))),
      shiny::column(3, shiny::wellPanel(shiny::h4("Procesos pendientes"), shiny::textOutput("pendientes"))),
      shiny::column(3, shiny::wellPanel(shiny::h4("Monto pendiente"), shiny::textOutput("monto_pendiente"))),
      shiny::column(3, shiny::wellPanel(shiny::h4("Operaciones en rojo"), shiny::textOutput("operaciones_rojas")))
    ),
    shiny::h3("Estado registrado de los procesos"),
    plotly::plotlyOutput("estado_plot", height = "500px"),
    shiny::p("Pendiente no equivale a retraso, el PSD no contiene todas las fechas de planificación y contratación.", class = "small-note")
  ),
  shiny::tabPanel(
    "Brecha",
    shiny::sidebarLayout(
      shiny::sidebarPanel(
        shiny::selectInput("pais", "Pais", choices = c("Todos", sort(unique(datos$pais))), selected = "Todos"),
        shiny::selectInput("sector", "Sector", choices = c("Todos", sort(unique(datos$sector_ibcie))), selected = "Todos"),
        shiny::sliderInput("edad", "Edad de la operación", min = min(datos$edad), max = max(datos$edad), value = c(min(datos$edad), max(datos$edad)), step = 1)
      ),
      shiny::mainPanel(plotly::plotlyOutput("brecha_plot", height = "650px"))
    )
  ),
  shiny::tabPanel(
    "Semaforo",
    shiny::fluidRow(
      shiny::column(8, DT::DTOutput("tabla_operaciones")),
      shiny::column(4, shiny::h4("Top 10 por monto pendiente esperado"), plotly::plotlyOutput("top_plot", height = "650px"))
    )
  ),
  shiny::tabPanel(
    "Modelo",
    shiny::h3("Odds ratios del logit binario"),
    plotly::plotlyOutput("odds_plot", height = "600px"),
    shiny::p("Un odds ratio mayor que 1 indica una correlacion positiva con la probabilidad de quedar pendiente.", class = "small-note"),
    shiny::p("La variable share_plan mide la participacion del presupuesto de un proceso dentro del monto total del plan de adquisiciones. La validacion LOOO compara operaciones no usadas en el ajuste con un benchmark constante.", class = "small-note")
  ),
  shiny::tabPanel(
    "Calculadora de riesgo",
    shiny::sidebarLayout(
      shiny::sidebarPanel(
        shiny::selectInput("categoria", "Categoria del proceso", choices = sort(unique(datos$categoria_proceso))),
        shiny::numericInput("monto", "Monto del proceso, USD", value = 1000000, min = 0),
        #share_plan is the process budget divided by the total plan budget
        shiny::numericInput("share_plan", "Participacion en el plan", value = 0.05, min = 0, max = 1.2, step = 0.001),
        shiny::helpText("Proporcion del presupuesto total del plan que corresponde a este proceso. En general va de 0 a 1. En los datos observados va de 0 a 1.14. Valores altos indican que el proceso representa una parte importante del plan."),
        shiny::numericInput("monto_aprobado", "Monto aprobado, USD", value = 50000000, min = 0),
        shiny::numericInput("plan_sobre_aprobado", "Plan / aprobado", value = 0.5, min = 0, max = 2.5, step = 0.01),
        shiny::helpText("Relacion entre el monto total del plan de adquisiciones y el monto aprobado de la operacion. Un valor de 1 significa que ambos montos son iguales. Menos de 1 significa que el plan es menor que el monto aprobado y mas de 1 significa que el plan es mayor. En los datos observados va aproximadamente de 0 a 2.35."),
        shiny::numericInput("n_procesos", "Numero de procesos", value = 10, min = 1, max = 523),
        shiny::helpText("Cantidad total de procesos de adquisicion registrados en la operacion. No es la cantidad de procesos del mismo tipo. En los datos observados va de 1 a 523 procesos por operacion."),
        shiny::numericInput("edad_proceso", "Edad de la operacion", value = 6, min = 0),
        shiny::actionButton("calcular", "Calcular probabilidad", class = "btn-primary")
      ),
      shiny::mainPanel(shiny::h3("Resultado"), shiny::textOutput("resultado_riesgo", container = shiny::div, inline = FALSE), shiny::p("Herramienta ilustrativa basada en correlaciones. No reemplaza una revision tecnica.", class = "small-note"))
    )
  ),
  shiny::tabPanel(
    "Metodologia",
    shiny::h3("Definiciones y limites"),
    shiny::tags$ul(
      shiny::tags$li("La unidad de analisis es el proceso de adquisicion."),
      shiny::tags$li("La muestra es un corte transversal de operaciones aprobadas hasta 2022."),
      shiny::tags$li("El modelo es un logit binario, pendiente frente a no pendiente."),
      shiny::tags$li("El semaforo agrega probabilidades predichas por monto a nivel de operacion."),
      shiny::tags$li("Pendiente no equivale a retraso porque no hay fechas completas de los hitos."),
      shiny::tags$li("La fuente es la Plataforma de Datos Abiertos del BCIE y la cobertura es parcial.")
    ),
    shiny::p(shiny::a("Repositorio en GitHub", href = "https://github.com/Emerson-nic/Second_Datathon_BCIE", target = "_blank"), class = "small-note")
  )
)

#server ----
server <- function(input, output, session) {
  datos_filtrados <- shiny::reactive({
    salida <- datos
    if (input$pais != "Todos") salida <- salida %>% dplyr::filter(pais == input$pais)
    if (input$sector != "Todos") salida <- salida %>% dplyr::filter(sector_ibcie == input$sector)
    salida %>% dplyr::filter(edad >= input$edad[1], edad <= input$edad[2])
  })

  output$brecha <- shiny::renderText(scales::percent(sum(datos$monto_presupuestado_proceso_adquisicion[datos$estado3 == "pendiente"]) / sum(datos$monto_presupuestado_proceso_adquisicion), accuracy = 0.1))
  output$pendientes <- shiny::renderText(scales::percent(mean(datos$estado3 == "pendiente"), accuracy = 0.1))
  output$monto_pendiente <- shiny::renderText(scales::dollar(sum(datos$monto_presupuestado_proceso_adquisicion[datos$estado3 == "pendiente"]), accuracy = 1))
  output$operaciones_rojas <- shiny::renderText(sum(operaciones$semaforo_abs == "Rojo"))

  output$estado_plot <- plotly::renderPlotly({
    estado <- datos %>% dplyr::count(estado3) %>% dplyr::mutate(estado3 = factor(estado3, levels = names(paleta_estado)))
    grafico <- ggplot2::ggplot(estado, ggplot2::aes(x = estado3, y = n, fill = estado3, text = paste0("Procesos: ", n))) +
      ggplot2::geom_col() + ggplot2::scale_fill_manual(values = paleta_estado) + ggplot2::labs(x = "Estado", y = "Procesos", fill = "Estado") + tema
    plotly::ggplotly(grafico, tooltip = "text")
  })

  output$brecha_plot <- plotly::renderPlotly({
    filtrado <- datos_filtrados() %>% dplyr::group_by(pais) %>% dplyr::summarise(brecha = sum(monto_presupuestado_proceso_adquisicion[estado3 == "pendiente"]) / sum(monto_presupuestado_proceso_adquisicion), procesos = dplyr::n(), .groups = "drop") %>% dplyr::arrange(brecha)
    grafico <- ggplot2::ggplot(filtrado, ggplot2::aes(x = brecha, y = reorder(pais, brecha), text = paste0("Pais: ", pais, "<br>Brecha: ", scales::percent(brecha), "<br>Procesos: ", procesos))) + ggplot2::geom_col(fill = "#1F4E79") + ggplot2::scale_x_continuous(labels = scales::percent) + ggplot2::labs(x = "Brecha observada", y = "Pais") + tema
    plotly::ggplotly(grafico, tooltip = "text")
  })

  output$tabla_operaciones <- DT::renderDT({
    tabla <- operaciones %>% dplyr::arrange(dplyr::desc(monto_pendiente))
    DT::datatable(tabla, filter = "top", extensions = "Buttons", options = list(dom = "Bfrtip", buttons = c("copy", "csv", "print"), pageLength = 10), rownames = FALSE) %>% DT::formatPercentage(c("share_pendiente", "share_obs", "pred_looo", "obs"), 1)
  })

  output$top_plot <- plotly::renderPlotly({
    top <- operaciones %>% dplyr::arrange(dplyr::desc(monto_pendiente)) %>% dplyr::slice_head(n = 10)
    grafico <- ggplot2::ggplot(top, ggplot2::aes(x = monto_pendiente, y = reorder(numero_prestamo, monto_pendiente), text = pais)) + ggplot2::geom_col(fill = "#C62828") + ggplot2::scale_x_continuous(labels = scales::label_dollar()) + ggplot2::labs(x = "Monto pendiente esperado", y = "Prestamo") + tema
    plotly::ggplotly(grafico, tooltip = "text")
  })

  output$odds_plot <- plotly::renderPlotly({
    co <- coeficientes %>% dplyr::filter(termino != "(Intercept)")
    grafico <- ggplot2::ggplot(co, ggplot2::aes(x = odds_ratio, y = reorder(termino, odds_ratio), text = paste0("p-valor: ", round(p_valor, 4)))) + ggplot2::geom_vline(xintercept = 1, linetype = "dashed") + ggplot2::geom_point() + ggplot2::scale_x_log10() + ggplot2::labs(x = "Odds ratio", y = NULL) + tema
    plotly::ggplotly(grafico, tooltip = "text")
  })

  shiny::observeEvent(input$calcular, {
    eta <- coeficientes$coeficiente[coeficientes$termino == "(Intercept)"]
    termino_categoria <- paste0("categoria_proceso", input$categoria)
    if (termino_categoria %in% coeficientes$termino) eta <- eta + coeficientes$coeficiente[coeficientes$termino == termino_categoria]
    valores <- c(log_monto_proceso = log1p(input$monto), share_plan = input$share_plan, log_monto_aprobado = log1p(input$monto_aprobado), plan_sobre_aprobado = input$plan_sobre_aprobado, n_procesos = input$n_procesos, edad = input$edad_proceso)
    for (nombre in names(valores)) eta <- eta + coeficientes$coeficiente[coeficientes$termino == nombre] * valores[[nombre]]
    probabilidad <- 1 / (1 + exp(-eta))
    output$resultado_riesgo <- shiny::renderText(paste0("Probabilidad estimada de quedar pendiente: ", scales::percent(probabilidad, accuracy = 0.1)))
  })
}

#launch app ----
shiny::shinyApp(ui = ui, server = server)
