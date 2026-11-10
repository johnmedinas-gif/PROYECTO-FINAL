defmodule Emergencias.PersonasServer do
  @moduledoc "GenServer de personas afectadas y mensajes entre familiares."
  use GenServer
  alias Emergencias.{Almacen, Util, ZonasServer}
  alias Emergencias.Dominio.{Mensaje, Persona}

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def reportar(documento, nombre, zona, estado, edad, usuario),
    do: GenServer.call(__MODULE__, {:reportar, documento, nombre, zona, estado, edad, usuario})

  def obtener(documento), do: GenServer.call(__MODULE__, {:obtener, Util.id(documento)})
  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})
  def cambiar_estado(documento, estado, usuario), do: GenServer.call(__MODULE__, {:estado, Util.id(documento), estado, usuario})
  def enviar_mensaje(remitente, documento, contenido), do: GenServer.call(__MODULE__, {:mensaje, remitente, documento, contenido})
  def mensajes(documento \\ nil), do: GenServer.call(__MODULE__, {:mensajes, documento && Util.id(documento)})
  def entregar_mensaje(id), do: GenServer.call(__MODULE__, {:entregar, Util.id(id)})

  @impl true
  def init(_) do
    mensajes = Almacen.todos(:mensajes)
    {:ok, %{personas: Almacen.todos(:personas), mensajes: mensajes, siguiente: Util.siguiente_numero(Map.keys(mensajes), "MSG")}}
  end

  @impl true
  def handle_call({:reportar, doc, nombre, zona, estado, edad, usuario}, _from, st) do
    with {:ok, p} <- Persona.crear(doc, nombre, edad, zona, estado, usuario),
         true <- ZonasServer.existe?(p.zona) || {:error, :zona_no_existe},
         false <- Map.has_key?(st.personas, p.documento) || false do
      {:reply, {:ok, p}, guardar_persona(st, p)}
    else
      true -> {:reply, {:error, :ya_existe}, st}
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:obtener, doc}, _from, st), do: {:reply, fetch(st.personas, doc, :persona_no_existe), st}

  def handle_call({:listar, filtros}, _from, st),
    do: {:reply, st.personas |> Map.values() |> Persona.buscar(filtros) |> Enum.sort_by(& &1.documento), st}

  def handle_call({:estado, doc, estado, usuario}, _from, st) do
    with {:ok, p} <- fetch(st.personas, doc, :persona_no_existe),
         {:ok, p} <- Persona.cambiar_estado(p, estado, usuario) do
      {:reply, {:ok, p}, guardar_persona(st, p)}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:mensaje, remitente, doc, contenido}, _from, st) do
    id = Util.formato_id("MSG", st.siguiente)

    with {:ok, m} <- Mensaje.crear(id, remitente, doc, contenido) do
      {:reply, {:ok, m}, guardar_mensaje(%{st | siguiente: st.siguiente + 1}, m)}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:mensajes, doc}, _from, st) do
    lista = st.mensajes |> Map.values() |> Enum.filter(&(is_nil(doc) or &1.destinatario == doc)) |> Enum.sort_by(& &1.id)
    {:reply, lista, st}
  end

  def handle_call({:entregar, id}, _from, st) do
    with {:ok, m} <- fetch(st.mensajes, id, :no_encontrado),
         {:ok, m} <- Mensaje.entregar(m) do
      {:reply, {:ok, m}, guardar_mensaje(st, m)}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  defp fetch(mapa, clave, error), do: with(:error <- Map.fetch(mapa, clave), do: {:error, error})

  defp guardar_persona(st, p) do
    Almacen.put(:personas, p.documento, p)
    %{st | personas: Map.put(st.personas, p.documento, p)}
  end

  defp guardar_mensaje(st, m) do
    Almacen.put(:mensajes, m.id, m)
    %{st | mensajes: Map.put(st.mensajes, m.id, m)}
  end
end
