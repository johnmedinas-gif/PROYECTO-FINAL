defmodule Emergencias.Util do
  @moduledoc "Funciones puras de apoyo: normalización de texto, validaciones numéricas y filtros."

  @doc "Minúsculas, sin tildes y sin espacios sobrantes."
  def normalizar(texto) do
    texto
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end

  @doc "Código de zona/categoría: normalizado y con guiones bajos."
  def codigo(texto), do: texto |> normalizar() |> String.replace(~r/\s+/, "_")

  @doc "Identificador de entidad (necesidad, recurso, albergue, documento): mayúsculas."
  def id(texto), do: texto |> to_string() |> String.trim() |> String.upcase()

  def ahora, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  def parse_entero(n) when is_integer(n), do: {:ok, n}

  def parse_entero(texto) when is_binary(texto) do
    case Integer.parse(String.trim(texto)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :no_es_numero}
    end
  end

  def parse_entero(_), do: {:error, :no_es_numero}

  @doc "Entero estrictamente positivo."
  def cantidad(valor) do
    with {:ok, n} <- parse_entero(valor) do
      cond do
        n < 0 -> {:error, :cantidad_negativa}
        n == 0 -> {:error, :cantidad_invalida}
        true -> {:ok, n}
      end
    end
  end

  @doc "Entero mayor o igual a cero."
  def no_negativo(valor) do
    with {:ok, n} <- parse_entero(valor) do
      if n < 0, do: {:error, :cantidad_negativa}, else: {:ok, n}
    end
  end

  def no_vacio(texto, error \\ :campo_vacio) do
    if String.trim(to_string(texto)) == "", do: {:error, error}, else: :ok
  end

  @doc "Convierte texto del usuario a un átomo de una lista blanca (evita crear átomos arbitrarios)."
  def elegir(valor, validos, error) do
    buscado = codigo(to_string(valor))

    case Enum.find(validos, &(Atom.to_string(&1) == buscado)) do
      nil -> {:error, error}
      atomo -> {:ok, atomo}
    end
  end

  @doc "Filtra mapas por igualdad (normalizada) de los campos indicados."
  def filtrar(lista, filtros) do
    Enum.filter(lista, fn item ->
      Enum.all?(filtros, fn {campo, valor} ->
        codigo(to_string(Map.get(item, campo))) == codigo(to_string(valor))
      end)
    end)
  end

  def siguiente_numero(ids, prefijo) do
    ids
    |> Enum.map(fn id ->
      case Integer.parse(String.replace_prefix(id, prefijo, "")) do
        {n, _} -> n
        :error -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  def formato_id(prefijo, n), do: prefijo <> String.pad_leading(Integer.to_string(n), 3, "0")
end
