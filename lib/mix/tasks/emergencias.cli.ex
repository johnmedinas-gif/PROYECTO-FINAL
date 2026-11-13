defmodule Mix.Tasks.Emergencias.Cli do
  @shortdoc "Inicia la consola interactiva del sistema de emergencias"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    Emergencias.CLI.iniciar()
  end
end
