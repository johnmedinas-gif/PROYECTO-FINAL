defmodule Emergencias.Almacen do
  @moduledoc """
  Persistencia en archivos de texto plano (`data/<archivo>.txt`), un registro por línea
  con el formato `{clave, registro}` escrito con `inspect/2`. Un único proceso serializa
  las escrituras (evita carreras entre servidores) y escribe de forma atómica
  (archivo temporal + rename). Al iniciar recarga todo desde disco.
  """
  use GenServer
  require Logger

  @archivos [:usuarios, :actividad, :zonas, :necesidades, :recursos, :movimientos, :personas, :mensajes, :mascotas, :albergues]

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def put(archivo, clave, registro), do: GenServer.call(__MODULE__, {:put, archivo, clave, registro})
  def delete(archivo, clave), do: GenServer.call(__MODULE__, {:delete, archivo, clave})
  def get(archivo, clave), do: GenServer.call(__MODULE__, {:get, archivo, clave})
  def todos(archivo), do: GenServer.call(__MODULE__, {:todos, archivo})

  def directorio, do: Application.get_env(:emergencias, :data_dir, "data")
  defp ruta(archivo), do: Path.join(directorio(), "#{archivo}.txt")

  @impl true
  def init(_) do
    File.mkdir_p!(directorio())
    {:ok, Map.new(@archivos, &{&1, cargar(&1)})}
  end

  @impl true
  def handle_call({:put, archivo, clave, registro}, _from, estado) do
    datos = Map.put(Map.fetch!(estado, archivo), clave, registro)
    escribir(archivo, datos)
    {:reply, :ok, Map.put(estado, archivo, datos)}
  end

  def handle_call({:delete, archivo, clave}, _from, estado) do
    datos = Map.delete(Map.fetch!(estado, archivo), clave)
    escribir(archivo, datos)
    {:reply, :ok, Map.put(estado, archivo, datos)}
  end

  def handle_call({:get, archivo, clave}, _from, estado),
    do: {:reply, estado |> Map.fetch!(archivo) |> Map.get(clave), estado}

  def handle_call({:todos, archivo}, _from, estado), do: {:reply, Map.fetch!(estado, archivo), estado}

  defp escribir(archivo, datos) do
    destino = ruta(archivo)
    temporal = destino <> ".tmp"

    contenido =
      datos
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join("", fn par -> inspect(par, limit: :infinity, printable_limit: :infinity, width: :infinity) <> "\n" end)

    File.write!(temporal, contenido)
    File.rename!(temporal, destino)
  end

  defp cargar(archivo) do
    if File.exists?(ruta(archivo)) do
      ruta(archivo)
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.reduce(%{}, fn linea, acc ->
        try do
          {{clave, registro}, _} = Code.eval_string(linea)
          Map.put(acc, clave, registro)
        rescue
          e ->
            Logger.warning("Línea inválida en #{archivo}.txt: #{Exception.message(e)}")
            acc
        end
      end)
    else
      %{}
    end
  end
end
