defmodule Emergencias.RecursosServer do
  @moduledoc """
  GenServer del inventario. Es el ÚNICO punto por el que se modifica el stock, por lo que
  todas las operaciones (entradas, salidas, transferencias y reservas) se procesan una a una
  en su buzón de mensajes: la cantidad asignada nunca puede superar el inventario real.
  """
  use GenServer
  alias Emergencias.{Almacen, Recursion, Util, ZonasServer}
  alias Emergencias.Dominio.Recurso

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def registrar(attrs, usuario), do: GenServer.call(__MODULE__, {:registrar, attrs, usuario})
  def entrada(codigo, n, usuario), do: GenServer.call(__MODULE__, {:entrada, Util.id(codigo), n, usuario})
  def salida(codigo, n, usuario), do: GenServer.call(__MODULE__, {:salida, Util.id(codigo), n, usuario})
  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, Util.id(codigo)})
  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})
  def criticos, do: GenServer.call(__MODULE__, :criticos)
  def movimientos(codigo \\ nil), do: GenServer.call(__MODULE__, {:movimientos, codigo && Util.id(codigo)})

  def disponibilidad(categoria, zona \\ nil) do
    listar(%{categoria: categoria} |> then(&if(zona, do: Map.put(&1, :zona, zona), else: &1)))
    |> Recursion.sumar_por(& &1.cantidad)
  end

  @doc "Toma `cantidad` de la categoría (prefiere lotes de la zona indicada). Operación atómica."
  def tomar(categoria, zona, cantidad, destino, usuario),
    do: GenServer.call(__MODULE__, {:tomar, categoria, Util.codigo(zona), cantidad, destino, usuario})

  def transferir(codigo, origen, destino, cantidad, usuario),
    do: GenServer.call(__MODULE__, {:transferir, Util.id(codigo), Util.codigo(origen), Util.codigo(destino), cantidad, usuario})

  @impl true
  def init(_) do
    movimientos = Almacen.todos(:movimientos)
    siguiente = (movimientos |> Map.keys() |> Enum.max(fn -> 0 end)) + 1
    {:ok, %{recursos: Almacen.todos(:recursos), movimientos: movimientos, siguiente: siguiente}}
  end

  @impl true
  def handle_call({:registrar, attrs, usuario}, _from, st) do
    with {:ok, r} <- Recurso.crear(attrs),
         :ok <- zona_existe(r.zona),
         :ok <- sin_duplicado(st, r.codigo) do
      st = st |> guardar(r) |> then(&if(r.cantidad > 0, do: mov(&1, :entrada, r.codigo, r.cantidad, usuario, "registro inicial"), else: &1))
      {:reply, {:ok, r}, st}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:entrada, codigo, n, usuario}, _from, st) do
    with {:ok, r} <- fetch(st, codigo),
         {:ok, r} <- Recurso.entrada(r, n) do
      {:ok, cant} = Util.cantidad(n)
      {:reply, {:ok, r}, st |> guardar(r) |> mov(:entrada, codigo, cant, usuario, "entrada manual")}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:salida, codigo, n, usuario}, _from, st) do
    with {:ok, r} <- fetch(st, codigo),
         {:ok, r} <- Recurso.salida(r, n) do
      {:ok, cant} = Util.cantidad(n)
      {:reply, {:ok, r}, st |> guardar(r) |> mov(:salida, codigo, cant, usuario, "salida manual")}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:obtener, codigo}, _from, st), do: {:reply, fetch(st, codigo), st}

  def handle_call({:listar, filtros}, _from, st) do
    lista = st.recursos |> Map.values() |> Util.filtrar(filtros) |> Enum.sort_by(& &1.codigo)
    {:reply, lista, st}
  end

  def handle_call(:criticos, _from, st),
    do: {:reply, st.recursos |> Map.values() |> Enum.filter(&Recurso.critico?/1) |> Enum.sort_by(& &1.cantidad), st}

  def handle_call({:movimientos, codigo}, _from, st) do
    lista = st.movimientos |> Map.values() |> Enum.filter(&(is_nil(codigo) or &1.recurso == codigo)) |> Enum.sort_by(& &1.id)
    {:reply, lista, st}
  end

  def handle_call({:tomar, categoria, zona, cantidad, destino, usuario}, _from, st) do
    with {:ok, cantidad} <- Util.cantidad(cantidad) do
      categoria = Util.codigo(categoria)

      lotes =
        st.recursos
        |> Map.values()
        |> Enum.filter(&(&1.categoria == categoria and &1.cantidad > 0))
        |> Recursion.ordenar(fn a, b -> {a.zona != zona, -a.cantidad, a.codigo} <= {b.zona != zona, -b.cantidad, b.codigo} end)
        |> Enum.map(&{&1.codigo, &1.cantidad})

      case Recursion.tomar_de_lotes(lotes, cantidad) do
        {tomados, 0} ->
          st =
            Enum.reduce(tomados, st, fn {codigo, cant}, acc ->
              {:ok, r} = Recurso.salida(Map.fetch!(acc.recursos, codigo), cant)
              acc |> guardar(r) |> mov(:asignacion, codigo, cant, usuario, "necesidad #{destino}")
            end)

          {:reply, {:ok, tomados}, st}

        {_, _faltante} ->
          {:reply, {:error, :inventario_insuficiente}, st}
      end
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  def handle_call({:transferir, codigo, origen, destino, cantidad, usuario}, _from, st) do
    with {:ok, cant} <- Util.cantidad(cantidad),
         {:ok, r_origen} <- fetch(st, codigo),
         :ok <- if(r_origen.ubicacion == origen, do: :ok, else: {:error, :ubicacion_incorrecta}),
         :ok <- if(origen != destino, do: :ok, else: {:error, :mismo_centro}),
         {:ok, r_origen} <- Recurso.salida(r_origen, cant),
         {:ok, r_destino} <- lote_destino(st, r_origen, destino, cant) do
      st =
        st
        |> guardar(r_origen)
        |> guardar(r_destino)
        |> mov(:transferencia_salida, codigo, cant, usuario, "hacia #{destino}")
        |> mov(:transferencia_entrada, r_destino.codigo, cant, usuario, "desde #{origen}")

      {:reply, {:ok, r_origen, r_destino}, st}
    else
      {:error, _} = e -> {:reply, e, st}
    end
  end

  # Suma al lote equivalente del destino o crea uno nuevo "<codigo>@<destino>".
  defp lote_destino(st, r_origen, destino, cant) do
    existente = Enum.find(Map.values(st.recursos), &(&1.categoria == r_origen.categoria and &1.unidad == r_origen.unidad and &1.ubicacion == destino))

    if existente do
      Recurso.entrada(existente, cant)
    else
      Recurso.crear(%{codigo: "#{r_origen.codigo}@#{destino}", categoria: r_origen.categoria, cantidad: cant, unidad: r_origen.unidad, ubicacion: destino, zona: r_origen.zona})
    end
  end

  defp fetch(st, codigo), do: with(:error <- Map.fetch(st.recursos, codigo), do: {:error, :no_encontrado})
  defp zona_existe(zona), do: if(ZonasServer.existe?(zona), do: :ok, else: {:error, :zona_no_existe})
  defp sin_duplicado(st, codigo), do: if(Map.has_key?(st.recursos, codigo), do: {:error, :ya_existe}, else: :ok)

  defp guardar(st, r) do
    Almacen.put(:recursos, r.codigo, r)
    %{st | recursos: Map.put(st.recursos, r.codigo, r)}
  end

  defp mov(st, tipo, codigo, cantidad, usuario, detalle) do
    m = %{id: st.siguiente, tipo: tipo, recurso: codigo, cantidad: cantidad, usuario: usuario, fecha: Util.ahora(), detalle: detalle}
    Almacen.put(:movimientos, m.id, m)
    %{st | movimientos: Map.put(st.movimientos, m.id, m), siguiente: st.siguiente + 1}
  end
end
