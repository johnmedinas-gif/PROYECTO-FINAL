defmodule Emergencias.Application do
  @moduledoc """
  Árbol de supervisión. Estrategia `:rest_for_one`: si un hijo cae, se reinician él y los
  que dependen de él (los que están después). Todo el estado se recupera desde `Almacen`.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Emergencias.Almacen,
      {Registry, keys: :unique, name: Emergencias.SesionesRegistry},
      {Registry, keys: :unique, name: Emergencias.AlberguesRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Emergencias.SesionesSup},
      {DynamicSupervisor, strategy: :one_for_one, name: Emergencias.AlberguesSup},
      Emergencias.ZonasServer,
      Emergencias.RecursosServer,
      Emergencias.UsuariosServer,
      Emergencias.PersonasServer,
      Emergencias.MascotasServer,
      Emergencias.NecesidadesServer,
      Supervisor.child_spec({Task, &Emergencias.Albergues.restaurar/0}, restart: :temporary)
    ]

    Supervisor.start_link(children, strategy: :rest_for_one, name: Emergencias.Supervisor)
  end
end
