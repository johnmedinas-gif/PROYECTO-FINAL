defmodule Emergencias.UsuariosServer do
  @moduledoc "GenServer de usuarios: registro automático, autenticación y bitácora de actividad."
  use GenServer
  alias Emergencias.{Almacen, Sesiones, Util}
  alias Emergencias.Dominio.Usuario

  # Usuarios precargados (administradores del equipo). Se crean solo si todavía no existen.
  @semillas [
    {"john", "john123", "John Medina", "administrador", "centro"},
    {"daniel", "daniel123", "Daniel Montes", "administrador", "centro"}
  ]

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Conecta; si el usuario no existe lo registra automáticamente, si existe valida la contraseña."
  def conectar(username, password, tipo, zona, nombre),
    do: GenServer.call(__MODULE__, {:conectar, username, password, tipo, zona, nombre})

  def desconectar(username), do: GenServer.call(__MODULE__, {:desconectar, Util.codigo(username)})
  def obtener(username), do: GenServer.call(__MODULE__, {:obtener, Util.codigo(username)})
  def registrar_actividad(username, accion), do: GenServer.cast(__MODULE__, {:actividad, username, accion})
  def actividad(username \\ nil), do: GenServer.call(__MODULE__, {:ver_actividad, username && Util.codigo(username)})

  @impl true
  def init(_) do
    actividad = Almacen.todos(:actividad)
    {:ok, %{usuarios: sembrar(Almacen.todos(:usuarios)), actividad: actividad, siguiente: (actividad |> Map.keys() |> Enum.max(fn -> 0 end)) + 1}}
  end

  @impl true
  def handle_call({:conectar, username, password, tipo, zona, nombre}, _from, st) do
    clave = Util.codigo(username)

    case Map.fetch(st.usuarios, clave) do
      {:ok, usuario} ->
        with :ok <- Usuario.autenticar(usuario, password),
             {:ok, _} <- Sesiones.abrir(Usuario.publico(usuario)) do
          {:reply, {:ok, Usuario.publico(usuario), :autenticado}, st}
        else
          {:error, _} = e -> {:reply, e, st}
        end

      :error ->
        with {:ok, usuario} <- Usuario.crear(username, password, nombre, tipo, zona),
             {:ok, _} <- Sesiones.abrir(Usuario.publico(usuario)) do
          Almacen.put(:usuarios, usuario.username, usuario)
          {:reply, {:ok, Usuario.publico(usuario), :registrado}, %{st | usuarios: Map.put(st.usuarios, usuario.username, usuario)}}
        else
          {:error, _} = e -> {:reply, e, st}
        end
    end
  end

  def handle_call({:desconectar, username}, _from, st), do: {:reply, Sesiones.cerrar(username), st}

  def handle_call({:obtener, username}, _from, st),
    do: {:reply, with(:error <- Map.fetch(st.usuarios, username), do: {:error, :no_encontrado}), st}

  def handle_call({:ver_actividad, username}, _from, st) do
    lista = st.actividad |> Map.values() |> Enum.filter(&(is_nil(username) or &1.usuario == username)) |> Enum.sort_by(& &1.id)
    {:reply, lista, st}
  end

  @impl true
  def handle_cast({:actividad, username, accion}, st) do
    registro = %{id: st.siguiente, usuario: username, accion: accion, fecha: Util.ahora()}
    Almacen.put(:actividad, registro.id, registro)
    {:noreply, %{st | actividad: Map.put(st.actividad, registro.id, registro), siguiente: st.siguiente + 1}}
  end

  defp sembrar(usuarios) do
    Enum.reduce(@semillas, usuarios, fn {username, password, nombre, tipo, zona}, acc ->
      if Map.has_key?(acc, Util.codigo(username)) do
        acc
      else
        {:ok, usuario} = Usuario.crear(username, password, nombre, tipo, zona)
        Almacen.put(:usuarios, usuario.username, usuario)
        Map.put(acc, usuario.username, usuario)
      end
    end)
  end
end
