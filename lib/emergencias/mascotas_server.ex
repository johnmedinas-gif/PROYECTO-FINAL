defmodule Emergencias.MascotasServer do
  @moduledoc "GenServer de reportes de mascotas perdidas/encontradas y sus coincidencias."
  use GenServer
  alias Emergencias.{Almacen, Util, ZonasServer}
  alias Emergencias.Dominio.Mascota

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def reportar(attrs, usuario), do: GenServer.call(__MODULE__, {:reportar, attrs, usuario})
  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})
  def buscar_coincidencias, do: GenServer.call(__MODULE__, :coincidencias)
  def confirmar(id_perdida, id_encontrada, usuario), do: GenServer.call(__MODULE__, {:confirmar, Util.id(id_perdida), Util.id(id_encontrada), usuario})

  @impl true
  def init(_) do
    mascotas = Almacen.todos(:mascotas)
    {:ok, %{mascotas: mascotas, siguiente: Util.siguiente_numero(Map.keys(mascotas), "M")}}
  end

  @impl true
  def handle_call({:reportar, attrs, usuario}, _from, st) do
    id = Util.formato_id("M", st.siguiente)

    with {:ok, m} <- Mascota.crear(id, attrs, usuario),
         true <- ZonasServer.existe?(m.zona) || {:error, :zona_no_existe} do
      {:reply, {:ok, m}, guardar(%{st | siguiente: st.siguiente + 1}, m)}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:listar, filtros}, _from, st),
    do: {:reply, st.mascotas |> Map.values() |> Util.filtrar(filtros) |> Enum.sort_by(& &1.id), st}

  def handle_call(:coincidencias, _from, st) do
    pares = st.mascotas |> Map.values() |> Mascota.coincidencias()

    st =
      Enum.reduce(pares, st, fn {perdida, encontrada, puntaje}, acc ->
        acc |> marcar(perdida, encontrada, puntaje) |> marcar(encontrada, perdida, puntaje)
      end)

    {:reply, pares, st}
  end

  def handle_call({:confirmar, id_p, id_e, usuario}, _from, st) do
    with {:ok, p} <- fetch(st, id_p),
         {:ok, e} <- fetch(st, id_e),
         :ok <- if(p.tipo == :perdida and e.tipo == :encontrada, do: :ok, else: {:error, :tipos_incorrectos}),
         {:ok, p} <- Mascota.resolver(p, e.id),
         {:ok, e} <- Mascota.resolver(e, p.id) do
      _ = usuario
      {:reply, {:ok, p, e}, st |> guardar(p) |> guardar(e)}
    else
      {:error, _} = err -> {:reply, err, st}
    end
  end

  defp marcar(st, id, otro, puntaje) do
    m = Map.fetch!(st.mascotas, id)
    candidatos = Enum.uniq_by([%{id: otro, puntaje: puntaje} | m.candidatos], & &1.id)
    guardar(st, %{m | estado: :posible_coincidencia, candidatos: candidatos})
  end

  defp fetch(st, id), do: with(:error <- Map.fetch(st.mascotas, id), do: {:error, :no_encontrado})

  defp guardar(st, m) do
    Almacen.put(:mascotas, m.id, m)
    %{st | mascotas: Map.put(st.mascotas, m.id, m)}
  end
end
