defmodule Emergencias.Dominio.Albergue do
  @moduledoc "Reglas puras de un albergue. Los alojados se guardan en un MapSet (sin duplicados)."
  alias Emergencias.Util

  def nuevo(codigo, nombre, zona, capacidad) do
    with :ok <- Util.no_vacio(codigo),
         :ok <- Util.no_vacio(nombre),
         :ok <- Util.no_vacio(zona, :zona_invalida),
         {:ok, cap} <- Util.cantidad(capacidad) do
      {:ok,
       %{
         codigo: Util.id(codigo),
         nombre: String.trim(nombre),
         zona: Util.codigo(zona),
         capacidad: cap,
         personas: MapSet.new(),
         necesidades: MapSet.new(),
         recursos: MapSet.new()
       }}
    end
  end

  def ocupacion(a), do: MapSet.size(a.personas)
  def cupos(a), do: a.capacidad - ocupacion(a)
  def porcentaje(a), do: Float.round(ocupacion(a) * 100 / a.capacidad, 1)

  def ingresar(a, documento) do
    cond do
      MapSet.member?(a.personas, documento) -> {:error, :ya_ingresado}
      cupos(a) <= 0 -> {:error, :sin_cupo}
      true -> {:ok, %{a | personas: MapSet.put(a.personas, documento)}}
    end
  end

  def salir(a, documento) do
    if MapSet.member?(a.personas, documento),
      do: {:ok, %{a | personas: MapSet.delete(a.personas, documento)}},
      else: {:error, :no_esta_en_albergue}
  end

  def vincular(a, :necesidad, id), do: %{a | necesidades: MapSet.put(a.necesidades, id)}
  def vincular(a, :recurso, id), do: %{a | recursos: MapSet.put(a.recursos, id)}

  # Persistencia en texto plano: los MapSet se guardan como listas.
  def exportar(a),
    do: %{a | personas: MapSet.to_list(a.personas), necesidades: MapSet.to_list(a.necesidades), recursos: MapSet.to_list(a.recursos)}

  def importar(r),
    do: %{r | personas: MapSet.new(r.personas), necesidades: MapSet.new(r.necesidades), recursos: MapSet.new(r.recursos)}
end
