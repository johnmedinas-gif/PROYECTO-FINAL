defmodule Emergencias.Demo do
  @moduledoc """
  Reproduce el flujo de ejemplo del enunciado y demuestra un conflicto concurrente:
  50 litros de agua y dos solicitudes simultáneas (30 y 25 litros) más una ráfaga de
  20 solicitudes concurrentes de 5 litros contra un inventario de 50.
  """
  alias Emergencias.{Comandos, RecursosServer}

  def correr do
    titulo("1. Usuarios conectados (cada uno en su propio proceso)")
    laura = login("connect laura 1234 coordinador centro \"Laura Gómez\"")
    {:ok, _, ana} = Comandos.ejecutar("connect ana 1234 ciudadano centro", nil)
    {:ok, _, vol} = Comandos.ejecutar("connect pedro 1234 voluntario zona_norte", nil)

    titulo("2. Zonas, sectores y puntos de atención (árbol recursivo)")
    run(laura, "register_zone centro \"Zona Centro\" critico 500")
    run(laura, "register_sector centro sector3 \"Sector 3\" alto 300")
    run(laura, "register_point centro sector3 punto1 \"Punto de atención 1\" critico 120")
    run(laura, "register_zone zona_norte \"Zona Norte\" alto 200")
    run(laura, "zone_status centro")

    titulo("3. Necesidades y recursos")
    run(laura, "register_need agua 30 critica centro \"Punto de atención sector 3\"")
    run(ana, "register_need agua 25 alta centro \"Familias del sector 3\"")
    run(laura, "register_need alimentos 10 baja centro \"Refrigerios\"")
    run(laura, "register_resource R001 agua 50 litros centro_acopio_1 centro")
    run(laura, "pending_needs")

    titulo("4. CONFLICTO CONCURRENTE: dos solicitudes simultáneas sobre 50 L (30 + 25 = 55)")
    tareas = [
      Task.async(fn -> Comandos.ejecutar("assign_resource N001 agua 30", laura) end),
      Task.async(fn -> Comandos.ejecutar("assign_resource N002 agua 25", laura) end)
    ]

    for t <- tareas, do: imprimir(Task.await(t))
    run(laura, "list_resources")

    titulo("5. Ráfaga de 20 hilos pidiendo 5 L c/u (inventario total real: 20 L en R001 + 50 L en R002 = 70 L)")
    run(laura, "register_resource R002 agua 50 litros centro_acopio_2 centro")
    for i <- 1..20, do: run(laura, "register_need agua 5 media centro \"Ráfaga #{i}\"", false)
    ids = for n <- Emergencias.NecesidadesServer.listar() |> Enum.filter(&String.starts_with?(&1.descripcion, "Ráfaga")), do: n.id

    resultados =
      ids
      |> Task.async_stream(fn id -> Emergencias.NecesidadesServer.asignar(id, "agua", 5, "demo") end, max_concurrency: 20)
      |> Enum.map(fn {:ok, r} -> r end)

    ok = Enum.count(resultados, &match?({:ok, _, _}, &1))
    IO.puts("Asignaciones aceptadas: #{ok} | rechazadas: #{20 - ok}")
    IO.puts("Inventario restante: R001=#{elem(RecursosServer.obtener("R001"), 1).cantidad} L, R002=#{elem(RecursosServer.obtener("R002"), 1).cantidad} L (esperado: 14 aceptadas = 70 L, nunca negativo)")

    titulo("6. Personas, mensajes y albergue")
    run(ana, "report_person 1001 Andrés zona_norte localizada 30")
    run(laura, "register_shelter A01 \"Albergue Norte\" zona_norte 2")
    run(vol, "register_entry A01 1001")
    run(ana, "send_family_message 1001 \"Estoy bien, estoy en el albergue norte\"")
    run(ana, "list_family_messages 1001")
    run(ana, "find_person 1001")
    run(vol, "check_shelter A01")

    titulo("7. Mascotas y coincidencias")
    run(ana, "report_pet lost perro \"Luna\" negra mediana zona_norte 3001234567 collar rojo")
    run(vol, "report_pet found perro desconocido negra mediana zona_norte 3009876543 collar rojo")
    run(vol, "match_pets")
    run(laura, "confirm_match M001 M002")

    titulo("8. Resumen global (coordinador)")
    run(laura, "critical_resources")
    run(laura, "summary")
    :ok
  end

  defp login(linea), do: elem(Comandos.ejecutar(linea, nil), 2)

  defp run(usuario, linea, mostrar \\ true) do
    resultado = Comandos.ejecutar(linea, usuario)
    if mostrar do
      IO.puts("\n#{usuario.username}> #{linea}")
      imprimir(resultado)
    end
    resultado
  end

  defp imprimir({estado, texto, _}), do: IO.puts(if(estado == :error, do: "✗ " <> texto, else: texto))
  defp titulo(t), do: IO.puts("\n\n#{String.duplicate("=", 70)}\n#{t}\n#{String.duplicate("=", 70)}")
end
