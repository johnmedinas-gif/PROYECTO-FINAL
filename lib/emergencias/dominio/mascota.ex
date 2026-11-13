defmodule Emergencias.Dominio.Mascota do
  @moduledoc """
  Reportes de mascotas perdidas/encontradas y algoritmo de coincidencia.

  Puntaje de similitud (0-100) = suma ponderada de atributos:
  especie 30 (obligatoria: si difiere el puntaje es 0), color 20, tamaño 15 (parcial si es
  contiguo), zona 15, características 15 (índice de Jaccard de palabras) y nombre 5
  (solo si ambos lo conocen). Se considera coincidencia posible con puntaje >= 60.
  """
  alias Emergencias.{Recursion, Util}

  @tamanos [:pequeno, :mediano, :grande]
  @umbral 60
  @pesos [especie: 30, color: 20, tamano: 15, zona: 15, caracteristicas: 15, nombre: 5]
  @estados [:activa, :posible_coincidencia, :resuelta]

  def umbral, do: @umbral

  def crear(id, attrs, usuario) do
    with {:ok, tipo} <- tipo(attrs.tipo),
         :ok <- Util.no_vacio(attrs.especie),
         :ok <- Util.no_vacio(attrs.zona, :zona_invalida),
         :ok <- Util.no_vacio(attrs.contacto),
         {:ok, tamano} <- Util.elegir(Regex.replace(~r/a$/, Util.codigo(attrs.tamano), "o"), @tamanos, :tamano_invalido) do
      {:ok,
       %{
         id: id,
         tipo: tipo,
         especie: Util.codigo(attrs.especie),
         nombre: String.trim(attrs.nombre),
         color: Util.codigo(attrs.color),
         tamano: tamano,
         zona: Util.codigo(attrs.zona),
         contacto: String.trim(attrs.contacto),
         caracteristicas: String.trim(Map.get(attrs, :caracteristicas, "")),
         estado: :activa,
         candidatos: [],
         pareja: nil,
         reportada_por: usuario,
         fecha: Util.ahora()
       }}
    end
  end

  defp tipo(t) do
    case Util.codigo(t) do
      x when x in ["lost", "perdida"] -> {:ok, :perdida}
      x when x in ["found", "encontrada"] -> {:ok, :encontrada}
      _ -> {:error, :tipo_reporte_invalido}
    end
  end

  def estados, do: @estados

  def puntaje(a, b) do
    if a.especie == b.especie, do: acumular(@pesos, a, b), else: 0
  end

  # Recursión sobre la lista de atributos ponderados.
  defp acumular([], _a, _b), do: 0
  defp acumular([{campo, peso} | resto], a, b), do: round(peso * similitud(campo, a, b)) + acumular(resto, a, b)

  defp similitud(:caracteristicas, a, b) do
    pa = palabras(a.caracteristicas)
    pb = palabras(b.caracteristicas)
    union = MapSet.union(pa, pb) |> MapSet.size()
    if union == 0, do: 0.0, else: MapSet.size(MapSet.intersection(pa, pb)) / union
  end

  defp similitud(:nombre, a, b) do
    if desconocido?(a.nombre) or desconocido?(b.nombre), do: 0.0, else: igual(Util.codigo(a.nombre), Util.codigo(b.nombre))
  end

  defp similitud(:tamano, a, b) do
    dif = abs(indice(a.tamano) - indice(b.tamano))
    Map.get(%{0 => 1.0, 1 => 0.5}, dif, 0.0)
  end

  defp similitud(campo, a, b), do: igual(Map.fetch!(a, campo), Map.fetch!(b, campo))

  defp igual(x, y), do: if(x == y, do: 1.0, else: 0.0)
  defp indice(t), do: Enum.find_index(@tamanos, &(&1 == t))
  defp desconocido?(n), do: Util.codigo(n) in ["", "desconocido", "desconocida", "sin_nombre"]

  defp palabras(texto) do
    texto
    |> Util.normalizar()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.filter(&(String.length(&1) > 2))
    |> MapSet.new()
  end

  @doc "Pares {id_perdida, id_encontrada, puntaje} con puntaje >= umbral, de mayor a menor."
  def coincidencias(reportes) do
    abiertos = Enum.filter(reportes, &(&1.estado != :resuelta))
    perdidas = Enum.filter(abiertos, &(&1.tipo == :perdida))
    encontradas = Enum.filter(abiertos, &(&1.tipo == :encontrada))

    pares = for p <- perdidas, e <- encontradas, (s = puntaje(p, e)) >= @umbral, do: {p.id, e.id, s}
    Recursion.ordenar(pares, fn {_, _, s1}, {_, _, s2} -> s1 >= s2 end)
  end

  def resolver(m, pareja_id) do
    if m.estado == :resuelta, do: {:error, :ya_resuelto}, else: {:ok, %{m | estado: :resuelta, pareja: pareja_id}}
  end
end
