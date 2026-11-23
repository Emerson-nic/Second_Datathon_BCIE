Nota para revisiones de portafolio
================

# Tres mensajes para la gestión

1.  **La brecha debe leerse en monto y no solo en conteo.** Los procesos
    pendientes representan 19.3% de los registros y 27.0% del
    presupuesto de la muestra principal.
2.  **El semáforo ordena conversaciones, no asigna culpas.** Rojo
    identifica operaciones con una participación pendiente esperada alta
    según umbrales explícitos. La revisión debe incorporar contexto
    técnico y contractual.
3.  **La calidad del dato es parte de la solución.** Los procesos
    fracasados o desiertos pesan poco en monto, por lo que registrar
    montos y fechas de hitos permitiría una alerta más precisa.

# Cómo usarlo

En cada revisión, ordenar las operaciones por `monto_pendiente`, revisar
primero las rojas de mayor monto, contrastar la predicción con el estado
del expediente y documentar la acción de acompañamiento. Pendiente no
equivale a retraso: el PSD no contiene todas las fechas necesarias para
esa conclusión.

# Top 10

``` r
operaciones %>% dplyr::arrange(dplyr::desc(monto_pendiente)) %>% dplyr::slice_head(n = 10) %>% dplyr::select(numero_prestamo, pais, semaforo_abs, share_pendiente, monto_pendiente)
```

    ## # A tibble: 10 × 5
    ##    numero_prestamo pais             semaforo_abs share_pendiente monto_pendiente
    ##    <chr>           <chr>            <chr>                  <dbl>           <dbl>
    ##  1 2317            Costa Rica       Verde                  0.282      186645910.
    ##  2 2291            Nicaragua        Amarillo               0.360      126080120.
    ##  3 2220            Costa Rica       Verde                  0.178      109925589.
    ##  4 2231            Nicaragua        Verde                  0.298       89313929.
    ##  5 2236            Nicaragua        Verde                  0.269       64462575.
    ##  6 2300            República Domin… Amarillo               0.426       56970154.
    ##  7 2256            El Salvador      Amarillo               0.300       48197548.
    ##  8 2222            Nicaragua        Verde                  0.200       46304593.
    ##  9 2050C           Nicaragua        Amarillo               0.338       45834919.
    ## 10 2230            Guatemala        Verde                  0.143       43875759.
