defmodule Emergencias.ZonasServer do
  @moduledoc "GenServer con el árbol de zonas, sectores y puntos de atención."
  use GenServer
  alias Emergencias.{Almacen, Util}
  alias Emergencias.Dominio.Zona

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def registrar_zona(codigo, nombre, nivel, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:zona, codigo, nombre, nivel, afectados})

  def registrar_sector(zona, codigo, nombre, nivel, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:hijo, zona, [], :sector, codigo, nombre, nivel, afectados})

  def registrar_punto(zona, sector, codigo, nombre, nivel, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:hijo, zona, [Util.codigo(sector)], :punto, codigo, nombre, nivel, afectados})

  def listar, do: GenServer.call(__MODULE__, :listar)
  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def existe?(codigo), do: match?({:ok, _}, obtener(codigo))

  def estadisticas(codigo) do
    with {:ok, zona} <- obtener(codigo), do: {:ok, Zona.estadisticas(zona)}
  end

  @impl true
  def init(_), do: {:ok, Almacen.todos(:zonas)}

  @impl true
  def handle_call({:zona, codigo, nombre, nivel, afectados}, _from, zonas) do
    with {:ok, zona} <- Zona.nuevo(:zona, codigo, nombre, nivel, afectados),
         false <- Map.has_key?(zonas, zona.codigo) || false do
      {:reply, {:ok, zona}, guardar(zonas, zona)}
    else
      true -> {:reply, {:error, :ya_existe}, zonas}
      {:error, _} = error -> {:reply, error, zonas}
    end
  end

  def handle_call({:hijo, zona, ruta, tipo, codigo, nombre, nivel, afectados}, _from, zonas) do
    with {:ok, raiz} <- Map.fetch(zonas, Util.codigo(zona)) |> normalizar(:zona_no_existe),
         {:ok, hijo} <- Zona.nuevo(tipo, codigo, nombre, nivel, afectados),
         {:ok, raiz} <- Zona.registrar_hijo(raiz, ruta, hijo) do
      {:reply, {:ok, hijo}, guardar(zonas, raiz)}
    else
      {:error, _} = error -> {:reply, error, zonas}
    end
  end

  def handle_call(:listar, _from, zonas), do: {:reply, zonas |> Map.values() |> Enum.sort_by(& &1.codigo), zonas}

  def handle_call({:obtener, codigo}, _from, zonas),
    do: {:reply, Map.fetch(zonas, Util.codigo(codigo)) |> normalizar(:zona_no_existe), zonas}

  defp normalizar({:ok, _} = ok, _), do: ok
  defp normalizar(:error, error), do: {:error, error}

  defp guardar(zonas, zona) do
    Almacen.put(:zonas, zona.codigo, zona)
    Map.put(zonas, zona.codigo, zona)
  end
end
