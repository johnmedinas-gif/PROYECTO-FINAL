defmodule Mix.Tasks.Emergencias.Demo do
  @shortdoc "Ejecuta el flujo de ejemplo y la demostración de concurrencia (datos en tmp/demo_data)"
  use Mix.Task

  @impl true
  def run(_args) do
    File.rm_rf!("tmp/demo_data")
    Application.put_env(:emergencias, :data_dir, "tmp/demo_data")
    Mix.Task.run("app.start")
    Emergencias.Demo.correr()
  end
end
