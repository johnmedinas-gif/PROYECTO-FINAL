defmodule Emergencias.NecesidadesServer do
  @moduledoc """
  GenServer de necesidades. Asignar recursos es una operación en dos pasos (validar la
  necesidad + tomar inventario) que se ejecuta completa dentro de un único `handle_call`,
  de modo que una necesidad nunca se asigna dos veces ni consume recursos tras cerrarse.
  """
  use GenServer
  alias Emergencias.{Almacen, RecursosServer, Util, ZonasServer}
  alias Emergencias.Dominio.Necesidad

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def registrar(attrs, usuario), do: GenServer.call(__MODULE__, {:registrar, attrs, usuario})
  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, Util.id(id)})
  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})
  def pendientes, do: listar(%{estado: "pendiente"})
  def asignar(id, categoria, cantidad, usuario), do: GenServer.call(__MODULE__, {:asignar, Util.id(id), categoria, cantidad, usuario})
  def transicionar(id, estado, usuario), do: GenServer.call(__MODULE__, {:transicionar, Util.id(id), estado, usuario})

  @impl true
  def init(_) do
    necesidades = Almacen.todos(:necesidades)
    {:ok, %{necesidades: necesidades, siguiente: Util.siguiente_numero(Map.keys(necesidades), "N")}}
  end

  @impl true
  def handle_call({:registrar, attrs, usuario}, _from, st) do
    id = Util.formato_id("N", st.siguiente)

    with {:ok, n} <- Necesidad.crear(id, attrs, usuario),
         true <- ZonasServer.existe?(n.zona) || {:error, :zona_no_existe} do
      {:reply, {:ok, n}, guardar(%{st | siguiente: st.siguiente + 1}, n)}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:obtener, id}, _from, st), do: {:reply, fetch(st, id), st}

  def handle_call({:listar, filtros}, _from, st) do
    lista = st.necesidades |> Map.values() |> Util.filtrar(filtros) |> Necesidad.ordenar_por_prioridad()
    {:reply, lista, st}
  end

  def handle_call({:asignar, id, categoria, cantidad, usuario}, _from, st) do
    with {:ok, n} <- fetch(st, id),
         {:ok, cant} <- Util.cantidad(cantidad),
         :ok <- Necesidad.validar_asignacion(n, categoria, cant),
         {:ok, tomados} <- RecursosServer.tomar(categoria, n.zona, cant, n.id, usuario),
         {:ok, n} <- Necesidad.registrar_asignacion(n, tomados, cant, usuario) do
      {:reply, {:ok, n, tomados}, guardar(st, n)}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:transicionar, id, estado, usuario}, _from, st) do
    with {:ok, n} <- fetch(st, id),
         {:ok, n} <- Necesidad.transicionar(n, estado, usuario) do
      {:reply, {:ok, n}, guardar(st, n)}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  defp fetch(st, id), do: with(:error <- Map.fetch(st.necesidades, id), do: {:error, :no_encontrado})

  defp guardar(st, n) do
    Almacen.put(:necesidades, n.id, n)
    %{st | necesidades: Map.put(st.necesidades, n.id, n)}
  end
end
