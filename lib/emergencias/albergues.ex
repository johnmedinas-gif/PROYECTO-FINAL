defmodule Emergencias.AlbergueProceso do
  @moduledoc "Cada albergue es un proceso independiente (GenServer) supervisado por un DynamicSupervisor."
  use GenServer
  alias Emergencias.{Almacen, Albergues}
  alias Emergencias.Dominio.Albergue

  def start_link(albergue), do: GenServer.start_link(_MODULE_, albergue, name: Albergues.via(albergue.codigo))

  @impl true
  def init(albergue) do
    # Si el proceso fue reiniciado por el supervisor, recupera su último estado persistido.
    case Almacen.get(:albergues, albergue.codigo) do
      nil ->
        persistir(albergue)
        {:ok, albergue}

      registro ->
        {:ok, Albergue.importar(registro)}
    end
  end

  @impl true
  def handle_call(:consultar, _from, a), do: {:reply, a, a}

  def handle_call({:ingresar, doc}, _from, a), do: transicion(Albergue.ingresar(a, doc), a)
  def handle_call({:salir, doc}, _from, a), do: transicion(Albergue.salir(a, doc), a)

  def handle_call({:vincular, tipo, id}, _from, a) do
    nuevo = Albergue.vincular(a, tipo, id)
    persistir(nuevo)
    {:reply, {:ok, nuevo}, nuevo}
  end

  def handle_call(:crash, _from, _a), do: raise("caída simulada del albergue")

  defp transicion({:ok, nuevo}, _viejo) do
    persistir(nuevo)
    {:reply, {:ok, nuevo}, nuevo}
  end

  defp transicion({:error, _} = e, viejo), do: {:reply, e, viejo}

  defp persistir(a), do: Almacen.put(:albergues, a.codigo, Albergue.exportar(a))
end

defmodule Emergencias.Albergues do
  @moduledoc "API para gestionar los procesos de albergue (alta, consulta, ingresos y reportes)."
  alias Emergencias.{Almacen, AlbergueProceso, NecesidadesServer, RecursosServer, Recursion, Util, ZonasServer}
  alias Emergencias.Dominio.Albergue

  def via(codigo), do: {:via, Registry, {Emergencias.AlberguesRegistry, codigo}}

  def registrar(codigo, nombre, zona, capacidad) do
    with {:ok, albergue} <- Albergue.nuevo(codigo, nombre, zona, capacidad),
         true <- ZonasServer.existe?(albergue.zona) || {:error, :zona_no_existe} do
      case DynamicSupervisor.start_child(Emergencias.AlberguesSup, {AlbergueProceso, albergue}) do
        {:ok, _pid} -> {:ok, albergue}
        {:error, {:already_started, _}} -> {:error, :ya_existe}
        {:error, _} = e -> e
      end
    end
  end

  def restaurar do
    for {_codigo, registro} <- Almacen.todos(:albergues) do
      DynamicSupervisor.start_child(Emergencias.AlberguesSup, {AlbergueProceso, Albergue.importar(registro)})
    end

    :ok
  end

  def consultar(codigo) do
    case Registry.lookup(Emergencias.AlberguesRegistry, Util.id(codigo)) do
      [{pid, _}] -> {:ok, GenServer.call(pid, :consultar)}
      [] -> {:error, :albergue_no_existe}
    end
  end

  def ingresar(codigo, doc), do: llamar(codigo, {:ingresar, Util.id(doc)})
  def salir(codigo, doc), do: llamar(codigo, {:salir, Util.id(doc)})

  def vincular(codigo, tipo, id) do
    id = Util.id(id)

    with {:ok, _} <- existe_vinculo(tipo, id), do: llamar(codigo, {:vincular, tipo, id})
  end

  defp existe_vinculo(:necesidad, id), do: NecesidadesServer.obtener(id)
  defp existe_vinculo(:recurso, id), do: RecursosServer.obtener(id)

  defp llamar(codigo, mensaje) do
    case Registry.lookup(Emergencias.AlberguesRegistry, Util.id(codigo)) do
      [{pid, _}] -> GenServer.call(pid, mensaje)
      [] -> {:error, :albergue_no_existe}
    end
  end

  @doc "Consulta todos los albergues en paralelo (un Task por proceso)."
  def listar do
    Registry.select(Emergencias.AlberguesRegistry, [{{:, :"$1", :}, [], [:"$1"]}])
    |> Task.async_stream(&GenServer.call(&1, :consultar))
    |> Enum.map(fn {:ok, a} -> a end)
    |> Enum.sort_by(& &1.codigo)
  end

  def mas_ocupados(n \\ 5) do
    listar() |> Recursion.ordenar(fn a, b -> Albergue.porcentaje(a) >= Albergue.porcentaje(b) end) |> Enum.take(n)
  end

  def donde_esta(doc) do
    doc = Util.id(doc)
    Enum.find(listar(), &MapSet.member?(&1.personas, doc))
  end
end
