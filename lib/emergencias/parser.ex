defmodule Emergencias.Parser do
  @moduledoc "Análisis de las líneas de comando (recursivo sobre los caracteres, respeta comillas)."

  @doc ~S|Divide una línea en tokens: `send_msg 123 "hola mundo"` → ["send_msg", "123", "hola mundo"]|
  def tokenizar(linea), do: linea |> String.trim() |> String.graphemes() |> tokens([], "", false)

  defp tokens([], acc, actual, _comillas), do: Enum.reverse(agregar(acc, actual))
  defp tokens(["\"" | t], acc, actual, false), do: tokens(t, acc, actual, true)
  defp tokens(["\"" | t], acc, actual, true), do: tokens(t, [actual | acc], "", false)
  defp tokens([c | t], acc, actual, true), do: tokens(t, acc, actual <> c, true)
  defp tokens([c | t], acc, actual, false) when c in [" ", "\t"], do: tokens(t, agregar(acc, actual), "", false)
  defp tokens([c | t], acc, actual, false), do: tokens(t, acc, actual <> c, false)

  defp agregar(acc, ""), do: acc
  defp agregar(acc, actual), do: [actual | acc]

  @doc "Separa argumentos posicionales y filtros `clave=valor` (solo claves permitidas)."
  def filtros(args, permitidos) do
    Enum.reduce_while(args, {:ok, [], %{}}, fn arg, {:ok, posicionales, filtros} ->
      case String.split(arg, "=", parts: 2) do
        [clave, valor] ->
          case Enum.find(permitidos, &(Atom.to_string(&1) == String.downcase(clave))) do
            nil -> {:halt, {:error, {:filtro_invalido, clave}}}
            campo -> {:cont, {:ok, posicionales, Map.put(filtros, campo, valor)}}
          end

        [posicional] ->
          {:cont, {:ok, posicionales ++ [posicional], filtros}}
      end
    end)
  end
end
