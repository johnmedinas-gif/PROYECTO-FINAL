defmodule Emergencias.CLI do
  @moduledoc "Consola interactiva. Cada línea se interpreta con `Comandos.ejecutar/2`."
  alias Emergencias.{Comandos, UsuariosServer}

  def iniciar do
    IO.puts("""
    ==============================================================
     Sistema distribuido de coordinación de emergencias (Elixir)
     Escriba 'help' para ver los comandos y 'exit' para salir.
    ==============================================================
    """)

    loop(nil)
  end

  defp loop(usuario) do
    case IO.gets(prompt(usuario)) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      linea ->
        if String.trim(linea) in ["exit", "quit", "salir"] do
          if usuario, do: UsuariosServer.desconectar(usuario.username)
          IO.puts("Hasta pronto.")
        else
          {estado, texto, usuario} = Comandos.ejecutar(linea, usuario)
          if texto != "", do: IO.puts(if(estado == :error, do: "✗ " <> texto, else: texto))
          loop(usuario)
        end
    end
  end

  defp prompt(nil), do: "emergencias> "
  defp prompt(u), do: "#{u.username} (#{u.tipo}/#{u.zona})> "
end
