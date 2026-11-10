defmodule Emergencias.Fachada do
  @moduledoc "Operaciones que coordinan varios componentes (albergues + personas) y el resumen global."
  alias Emergencias.{Albergues, MascotasServer, NecesidadesServer, PersonasServer, RecursosServer, Recursion, ZonasServer}
  alias Emergencias.Dominio.{Albergue, Zona}

  def ingresar_albergue(codigo, documento, usuario) do
    with {:ok, _persona} <- PersonasServer.obtener(documento),
         :ok <- no_alojada(documento),
         {:ok, albergue} <- Albergues.ingresar(codigo, documento) do
      case PersonasServer.cambiar_estado(documento, "en_albergue", usuario) do
        {:ok, _} ->
          {:ok, albergue}

        {:error, _} = error ->
          # compensación: se revierte el ingreso si la persona no puede pasar a "en_albergue"
          Albergues.salir(codigo, documento)
          error
      end
    end
  end

  def salir_albergue(codigo, documento, usuario) do
    with {:ok, albergue} <- Albergues.salir(codigo, documento) do
      PersonasServer.cambiar_estado(documento, "localizada", usuario)
      {:ok, albergue}
    end
  end

  defp no_alojada(documento) do
    case Albergues.donde_esta(documento) do
      nil -> :ok
      _ -> {:error, :ya_alojada}
    end
  end

  def estado_zona(codigo) do
    with {:ok, zona} <- ZonasServer.obtener(codigo) do
      {:ok,
       %{
         zona: zona,
         estadisticas: Zona.estadisticas(zona),
         necesidades: NecesidadesServer.listar(%{zona: zona.codigo}),
         recursos: RecursosServer.listar(%{zona: zona.codigo}),
         albergues: Enum.filter(Albergues.listar(), &(&1.zona == zona.codigo)),
         mascotas: MascotasServer.listar(%{zona: zona.codigo}),
         personas: PersonasServer.listar(%{zona: zona.codigo})
       }}
    end
  end

  def resumen do
    zonas = ZonasServer.listar()
    necesidades = NecesidadesServer.listar()
    recursos = RecursosServer.listar()
    personas = PersonasServer.listar()
    mensajes = PersonasServer.mensajes()
    mascotas = MascotasServer.listar()
    albergues = Albergues.listar()

    %{
      zonas: length(zonas),
      afectados: Recursion.sumar_por(zonas, &Zona.total_afectados/1),
      necesidades: Recursion.contar_por(necesidades, & &1.estado),
      pendientes_criticas: Enum.count(necesidades, &(&1.estado == :pendiente and &1.prioridad == :critica)),
      stock: Recursion.sumar_por_clave(recursos, &{&1.categoria, &1.unidad}, & &1.cantidad),
      recursos_criticos: RecursosServer.criticos() |> length(),
      personas: Recursion.contar_por(personas, & &1.estado),
      mensajes: Recursion.contar_por(mensajes, & &1.estado),
      mascotas: Recursion.contar_por(mascotas, &{&1.tipo, &1.estado}),
      albergues: length(albergues),
      capacidad: Recursion.sumar_por(albergues, & &1.capacidad),
      ocupacion: Recursion.sumar_por(albergues, &Albergue.ocupacion/1)
    }
  end
end
