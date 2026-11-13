defmodule Emergencias.Dominio.Persona do
  @moduledoc "Personas afectadas, su máquina de estados y mensajes familiares."
  alias Emergencias.Util

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]
  @transiciones %{
    sin_informacion: [:reportada, :localizada],
    reportada: [:localizada, :trasladada, :en_albergue, :reunificada],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:localizada, :en_albergue, :reunificada],
    en_albergue: [:localizada, :trasladada, :reunificada],
    reunificada: []
  }

  def estados, do: @estados

  def crear(documento, nombre, edad, zona, estado, usuario) do
    with :ok <- Util.no_vacio(documento),
         :ok <- Util.no_vacio(nombre),
         :ok <- Util.no_vacio(zona, :zona_invalida),
         {:ok, estado} <- Util.elegir(estado, @estados -- [:reunificada], :estado_invalido),
         {:ok, edad} <- edad(edad) do
      ahora = Util.ahora()

      {:ok,
       %{
         documento: Util.id(documento),
         nombre: String.trim(nombre),
         edad: edad,
         zona: Util.codigo(zona),
         estado: estado,
         historial: [%{estado: estado, fecha: ahora, por: usuario}]
       }}
    end
  end

  defp edad(nil), do: {:ok, nil}
  defp edad(e), do: Util.no_negativo(e)

  def cambiar_estado(p, nuevo, usuario) do
    with {:ok, nuevo} <- Util.elegir(nuevo, @estados, :estado_invalido) do
      if nuevo in Map.fetch!(@transiciones, p.estado) do
        {:ok, %{p | estado: nuevo, historial: p.historial ++ [%{estado: nuevo, fecha: Util.ahora(), por: usuario}]}}
      else
        {:error, {:transicion_invalida, p.estado, nuevo}}
      end
    end
  end

  def buscar(personas, filtros) do
    Enum.filter(personas, fn p -> Enum.all?(filtros, fn {campo, valor} -> coincide(campo, p, valor) end) end)
  end

  defp coincide(:nombre, p, v), do: String.contains?(Util.normalizar(p.nombre), Util.normalizar(v))
  defp coincide(:documento, p, v), do: p.documento == Util.id(v)
  defp coincide(campo, p, v), do: Util.codigo(to_string(Map.fetch!(p, campo))) == Util.codigo(v)
end

defmodule Emergencias.Dominio.Mensaje do
  @moduledoc "Mensajes dirigidos a una persona o familia."
  alias Emergencias.Util

  def crear(id, remitente, documento, contenido) do
    with :ok <- Util.no_vacio(documento),
         :ok <- Util.no_vacio(contenido) do
      {:ok,
       %{
         id: id,
         fecha: Util.ahora(),
         remitente: remitente,
         destinatario: Util.id(documento),
         contenido: String.trim(contenido),
         estado: :pendiente
       }}
    end
  end

  def entregar(%{estado: :entregado}), do: {:error, :ya_entregado}
  def entregar(m), do: {:ok, %{m | estado: :entregado}}
end
