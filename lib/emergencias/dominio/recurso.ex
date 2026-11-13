defmodule Emergencias.Dominio.Recurso do
  @moduledoc "Reglas puras de un lote de inventario en un centro de apoyo."
  alias Emergencias.Util

  def crear(%{codigo: c, categoria: cat, cantidad: q, unidad: u, ubicacion: ub, zona: z}) do
    with :ok <- Util.no_vacio(c),
         :ok <- Util.no_vacio(cat),
         :ok <- Util.no_vacio(u),
         :ok <- Util.no_vacio(ub),
         :ok <- Util.no_vacio(z, :zona_invalida),
         {:ok, cantidad} <- Util.no_negativo(q) do
      {:ok,
       %{
         codigo: Util.id(c),
         nombre: String.trim(cat),
         categoria: Util.codigo(cat),
         cantidad: cantidad,
         maximo: cantidad,
         unidad: String.trim(u),
         ubicacion: Util.codigo(ub),
         zona: Util.codigo(z)
       }}
    end
  end

  def entrada(r, n) do
    with {:ok, n} <- Util.cantidad(n) do
      cantidad = r.cantidad + n
      {:ok, %{r | cantidad: cantidad, maximo: max(r.maximo, cantidad)}}
    end
  end

  def salida(r, n) do
    with {:ok, n} <- Util.cantidad(n) do
      if n > r.cantidad, do: {:error, :cantidad_insuficiente}, else: {:ok, %{r | cantidad: r.cantidad - n}}
    end
  end

  @doc "Crítico: queda el 25% o menos del máximo histórico del lote."
  def critico?(r), do: r.maximo > 0 and r.cantidad * 4 <= r.maximo
end
