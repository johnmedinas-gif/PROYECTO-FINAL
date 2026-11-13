defmodule Mix.Tasks.Emergencias.Menu do
  @shortdoc "Inicia el menú interactivo del sistema de emergencias"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    Emergencias.Menu.iniciar()
  end
end
