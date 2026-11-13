defmodule Emergencias.Dominio.Necesidad do
  @moduledoc "Reglas puras de una necesidad puntual: validación, estados y asignación."
  alias Emergencias.{Recursion, Util}

  @tipos [:agua, :alimentos, :medicamentos, :primeros_auxilios, :refugio, :transporte, :rescate, :otra]
  @prioridades [:critica, :alta, :media, :baja]
  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  def tipos, do: @tipos
  def prioridades, do: @prioridades
  def peso_prioridad(:critica), do: 4
  def peso_prioridad(:alta), do: 3
  def peso_prioridad(:media), do: 2
  def peso_prioridad(:baja), do: 1

  def crear(id, %{tipo: t, cantidad: c, prioridad: p, zona: z, descripcion: d}, responsable) do
    with {:ok, tipo} <- Util.elegir(t, @tipos, :tipo_invalido),
         {:ok, cantidad} <- Util.cantidad(c),
         {:ok, prioridad} <- Util.elegir(p, @prioridades, :prioridad_invalida),
         :ok <- Util.no_vacio(z, :zona_invalida),
         :ok <- Util.no_vacio(d, :campo_vacio) do
      ahora = Util.ahora()

      {:ok,
       %{
         id: id,
         tipo: tipo,
         descripcion: String.trim(d),
         cantidad: cantidad,
         asignado: 0,
         zona: Util.codigo(z),
         prioridad: prioridad,
         responsable: responsable,
         estado: :pendiente,
         creada_en: ahora,
         historial: [%{estado: :pendiente, fecha: ahora, por: responsable}],
         asignaciones: []
       }}
    end
  end

  def restante(n), do: n.cantidad - n.asignado

  @doc "Valida que la necesidad pueda consumir `cantidad` más y que la categoría corresponda."
  def validar_asignacion(n, categoria, cantidad) do
    cond do
      n.estado not in [:pendiente, :asignada, :en_atencion] -> {:error, :necesidad_cerrada}
      n.tipo != :otra and Atom.to_string(n.tipo) != Util.codigo(categoria) -> {:error, :categoria_no_coincide}
      cantidad > restante(n) -> {:error, :excede_requerido}
      true -> :ok
    end
  end

  def registrar_asignacion(n, tomados, cantidad, usuario) do
    ahora = Util.ahora()

    registro = Enum.map(tomados, fn {recurso, cant} -> %{recurso: recurso, cantidad: cant, fecha: ahora, por: usuario} end)
    n = %{n | asignado: n.asignado + cantidad, asignaciones: n.asignaciones ++ registro}
    if n.estado == :pendiente, do: transicionar(n, :asignada, usuario), else: {:ok, n}
  end

  def transicionar(n, nuevo, usuario) do
    with {:ok, nuevo} <- Util.elegir(nuevo, Map.keys(@transiciones), :estado_invalido) do
      if nuevo in Map.fetch!(@transiciones, n.estado) do
        {:ok,
         %{n | estado: nuevo, historial: n.historial ++ [%{estado: nuevo, fecha: Util.ahora(), por: usuario}]}}
      else
        {:error, {:transicion_invalida, n.estado, nuevo}}
      end
    end
  end

  @doc "La prioridad ordena la atención: críticas primero; a igual prioridad, la más antigua."
  def ordenar_por_prioridad(necesidades) do
    Recursion.ordenar(necesidades, fn a, b ->
      {-peso_prioridad(a.prioridad), a.id} <= {-peso_prioridad(b.prioridad), b.id}
    end)
  end
end
