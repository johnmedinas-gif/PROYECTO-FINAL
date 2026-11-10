defmodule Emergencias.Sesiones do
  @moduledoc "Una sesión = un proceso independiente por usuario conectado, bajo un DynamicSupervisor."

  defmodule Sesion do
    @moduledoc false
    use GenServer, restart: :temporary

    def start_link(usuario),
      do: GenServer.start_link(__MODULE__, usuario, name: {:via, Registry, {Emergencias.SesionesRegistry, usuario.username}})

    @impl true
    def init(usuario), do: {:ok, %{usuario: usuario, conectado_en: Emergencias.Util.ahora()}}

    @impl true
    def handle_call(:info, _from, st), do: {:reply, st, st}
  end

  def abrir(usuario) do
    case DynamicSupervisor.start_child(Emergencias.SesionesSup, {Sesion, usuario}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def cerrar(username) do
    case Registry.lookup(Emergencias.SesionesRegistry, username) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Emergencias.SesionesSup, pid)
      [] -> {:error, :no_conectado}
    end
  end

  def conectado?(username), do: Registry.lookup(Emergencias.SesionesRegistry, username) != []

  def conectados do
    Registry.select(Emergencias.SesionesRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}]) |> Enum.sort()
  end
end
