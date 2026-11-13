defmodule Emergencias.Dominio.Zona do
  @moduledoc """
  Árbol zona → sectores → puntos de atención. Todos los nodos tienen la misma forma
  (`tipo`, `codigo`, `nombre`, `nivel`, `afectados`, `hijos`), lo que permite funciones
  recursivas uniformes: `buscar/2`, `total_afectados/1`, `profundidad/1`,
  `contar_nodos/2`, `contar_por_nivel/2`, `nivel_maximo/1` y `agregar_hijo/3`.
  """
  alias Emergencias.{Recursion, Util}

  @niveles [:critico, :alto, :medio, :bajo]
  @hijo_de %{zona: :sector, sector: :punto}

  def niveles, do: @niveles
  def peso_nivel(:critico), do: 4
  def peso_nivel(:alto), do: 3
  def peso_nivel(:medio), do: 2
  def peso_nivel(:bajo), do: 1

  def nuevo(tipo, codigo, nombre, nivel, afectados) do
    with :ok <- Util.no_vacio(codigo),
         :ok <- Util.no_vacio(nombre),
         {:ok, nivel} <- Util.elegir(nivel, @niveles, :nivel_invalido),
         {:ok, afectados} <- Util.no_negativo(afectados) do
      {:ok,
       %{
         tipo: tipo,
         codigo: Util.codigo(codigo),
         nombre: String.trim(nombre),
         nivel: nivel,
         afectados: afectados,
         hijos: []
       }}
    end
  end

  @doc "Registra `hijo` bajo la ruta de códigos indicada (vacía = directamente bajo la raíz)."
  def registrar_hijo(raiz, ruta, hijo) do
    if buscar(raiz, hijo.codigo), do: {:error, :ya_existe}, else: agregar_hijo(raiz, ruta, hijo)
  end

  # Recursión: desciende por la ruta hasta el nodo padre.
  def agregar_hijo(nodo, [], hijo) do
    if @hijo_de[nodo.tipo] == hijo.tipo,
      do: {:ok, %{nodo | hijos: nodo.hijos ++ [hijo]}},
      else: {:error, :jerarquia_invalida}
  end

  def agregar_hijo(nodo, [codigo | ruta], hijo) do
    case Enum.split_while(nodo.hijos, &(&1.codigo != codigo)) do
      {_, []} ->
        {:error, :padre_no_existe}

      {antes, [objetivo | despues]} ->
        with {:ok, nuevo} <- agregar_hijo(objetivo, ruta, hijo),
             do: {:ok, %{nodo | hijos: antes ++ [nuevo | despues]}}
    end
  end

  def buscar(%{codigo: codigo} = nodo, codigo), do: nodo
  def buscar(%{hijos: hijos}, codigo), do: Enum.find_value(hijos, &buscar(&1, codigo))

  def total_afectados(nodo),
    do: nodo.afectados + Recursion.sumar_por(nodo.hijos, &total_afectados/1)

  def profundidad(nodo),
    do: 1 + (nodo.hijos |> Enum.map(&profundidad/1) |> Enum.max(fn -> 0 end))

  def contar_nodos(nodo, tipo) do
    propio = if nodo.tipo == tipo, do: 1, else: 0
    propio + Recursion.sumar_por(nodo.hijos, &contar_nodos(&1, tipo))
  end

  def contar_por_nivel(nodo, acc \\ %{}) do
    acc = Map.update(acc, nodo.nivel, 1, &(&1 + 1))
    Enum.reduce(nodo.hijos, acc, &contar_por_nivel/2)
  end

  def nivel_maximo(nodo) do
    [nodo.nivel | Enum.map(nodo.hijos, &nivel_maximo/1)] |> Enum.max_by(&peso_nivel/1)
  end

  def estadisticas(zona) do
    %{
      afectados: total_afectados(zona),
      sectores: contar_nodos(zona, :sector),
      puntos: contar_nodos(zona, :punto),
      por_nivel: contar_por_nivel(zona),
      nivel_maximo: nivel_maximo(zona),
      profundidad: profundidad(zona)
    }
  end
end
