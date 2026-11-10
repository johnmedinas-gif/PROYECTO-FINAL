defmodule Emergencias.Recursion do
  @moduledoc """
  Algoritmos recursivos propios sobre listas (no usan Enum para el recorrido principal):

    1. `sumar_por/2`        - suma un valor calculado por elemento
    2. `contar_por/2`       - frecuencia de una clave (recursión de cola con acumulador)
    3. `sumar_por_clave/3`  - suma agrupada por clave (recursión de cola)
    4. `ordenar/2`          - ordenamiento por mezcla (merge sort), usado para priorizar
    5. `tomar_de_lotes/2`   - reparte una cantidad entre varios lotes de inventario

  Además hay recursión sobre el árbol zona→sector→punto en `Dominio.Zona` y sobre
  el texto de los comandos en `Parser.tokenizar/1`.
  """

  def sumar_por([], _fun), do: 0
  def sumar_por([h | t], fun), do: fun.(h) + sumar_por(t, fun)

  def contar_por(lista, fun), do: contar_por(lista, fun, %{})
  defp contar_por([], _fun, acc), do: acc
  defp contar_por([h | t], fun, acc), do: contar_por(t, fun, Map.update(acc, fun.(h), 1, &(&1 + 1)))

  def sumar_por_clave(lista, clave, valor), do: sumar_por_clave(lista, clave, valor, %{})
  defp sumar_por_clave([], _c, _v, acc), do: acc

  defp sumar_por_clave([h | t], clave, valor, acc),
    do: sumar_por_clave(t, clave, valor, Map.update(acc, clave.(h), valor.(h), &(&1 + valor.(h))))

  @doc "Merge sort estable. `menor_o_igual.(a, b)` indica si `a` va antes (o igual) que `b`."
  def ordenar([], _cmp), do: []
  def ordenar([x], _cmp), do: [x]

  def ordenar(lista, cmp) do
    {izq, der} = Enum.split(lista, div(length(lista), 2))
    mezclar(ordenar(izq, cmp), ordenar(der, cmp), cmp)
  end

  defp mezclar([], der, _cmp), do: der
  defp mezclar(izq, [], _cmp), do: izq

  defp mezclar([a | ta] = izq, [b | tb] = der, cmp) do
    if cmp.(a, b), do: [a | mezclar(ta, der, cmp)], else: [b | mezclar(izq, tb, cmp)]
  end

  @doc """
  Reparte `faltante` unidades entre lotes `[{codigo, disponible}]` en orden.
  Devuelve `{[{codigo, tomado}], unidades_que_no_se_pudieron_cubrir}`.
  """
  def tomar_de_lotes(_lotes, 0), do: {[], 0}
  def tomar_de_lotes([], faltante), do: {[], faltante}

  def tomar_de_lotes([{codigo, disponible} | resto], faltante) do
    tomado = min(disponible, faltante)
    {tomados, pendiente} = tomar_de_lotes(resto, faltante - tomado)
    {[{codigo, tomado} | tomados], pendiente}
  end
end
