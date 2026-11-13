defmodule Emergencias.SistemaTest do
  use ExUnit.Case, async: false
  alias Emergencias.{Albergues, Comandos, NecesidadesServer, RecursosServer, ZonasServer}

  setup do
    ZonasServer.registrar_zona("zt", "Zona de prueba", "alto")
    :ok
  end

  defp u(n), do: "#{n}_#{System.unique_integer([:positive])}"

  test "CONCURRENCIA: nunca se asigna más del inventario" do
    cod = "RC#{System.unique_integer([:positive])}"
    {:ok, _} = RecursosServer.registrar(%{codigo: cod, categoria: "agua", cantidad: 50, unidad: "l", ubicacion: "c_conc", zona: "zt"}, "t")
    base = RecursosServer.disponibilidad("agua")

    ids =
      for i <- 1..20 do
        {:ok, n} = NecesidadesServer.registrar(%{tipo: "agua", cantidad: 5, prioridad: "alta", zona: "zt", descripcion: "c#{i}"}, "t")
        n.id
      end

    resultados =
      ids
      |> Task.async_stream(&NecesidadesServer.asignar(&1, "agua", 5, "t"), max_concurrency: 20)
      |> Enum.map(fn {:ok, r} -> r end)

    aceptadas = Enum.count(resultados, &match?({:ok, _, _}, &1))
    assert aceptadas == div(base, 5)
    assert RecursosServer.disponibilidad("agua") == base - aceptadas * 5
    assert Enum.all?(resultados, &(match?({:ok, _, _}, &1) or &1 == {:error, :inventario_insuficiente}))
  end

  test "una necesidad atendida no vuelve a consumir recursos ni se cierra dos veces" do
    {:ok, _} = RecursosServer.registrar(%{codigo: u("RN"), categoria: "medicamentos", cantidad: 100, unidad: "u", ubicacion: "c", zona: "zt"}, "t")
    {:ok, n} = NecesidadesServer.registrar(%{tipo: "medicamentos", cantidad: 10, prioridad: "alta", zona: "zt", descripcion: "m"}, "t")
    assert {:ok, _, _} = NecesidadesServer.asignar(n.id, "medicamentos", 10, "t")
    assert {:error, :excede_requerido} = NecesidadesServer.asignar(n.id, "medicamentos", 1, "t")
    {:ok, _} = NecesidadesServer.transicionar(n.id, "en_atencion", "t")
    {:ok, _} = NecesidadesServer.transicionar(n.id, "atendida", "t")
    assert {:error, :necesidad_cerrada} = NecesidadesServer.asignar(n.id, "medicamentos", 1, "t")
    assert {:error, {:transicion_invalida, _, _}} = NecesidadesServer.transicionar(n.id, "atendida", "t")
  end

  test "transferencia entre centros conserva el total e historial" do
    cod = u("RT")
    {:ok, _} = RecursosServer.registrar(%{codigo: cod, categoria: "alimentos", cantidad: 40, unidad: "kg", ubicacion: "acopio_t", zona: "zt"}, "t")
    {:ok, o, d} = RecursosServer.transferir(cod, "acopio_t", "albergue_t", 15, "t")
    assert o.cantidad + d.cantidad == 40
    assert {:error, :cantidad_insuficiente} = RecursosServer.transferir(cod, "acopio_t", "albergue_t", 999, "t")
    assert length(RecursosServer.movimientos(cod)) >= 2
    assert {:error, :ya_existe} = RecursosServer.registrar(%{codigo: cod, categoria: "x", cantidad: 1, unidad: "u", ubicacion: "c", zona: "zt"}, "t")
  end

  test "albergue concurrente: ocupación no supera la capacidad" do
    cod = u("A")
    {:ok, _} = Albergues.registrar(cod, "Albergue", "zt", 5)

    resultados =
      1..20 |> Task.async_stream(&Albergues.ingresar(cod, "DOC#{&1}"), max_concurrency: 20) |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 5
    {:ok, a} = Albergues.consultar(cod)
    assert MapSet.size(a.personas) == 5
  end

  test "SUPERVISIÓN: un albergue que cae se reinicia con su estado persistido" do
    cod = u("AS")
    {:ok, _} = Albergues.registrar(cod, "Resiliente", "zt", 10)
    {:ok, _} = Albergues.ingresar(cod, "777")
    [{pid, _}] = Registry.lookup(Emergencias.AlberguesRegistry, String.upcase(cod))
    ref = Process.monitor(pid)
    catch_exit(GenServer.call(pid, :crash))
    assert_receive {:DOWN, ^ref, _, _, _}, 1_000
    Process.sleep(100)
    assert {:ok, a} = Albergues.consultar(cod)
    assert MapSet.member?(a.personas, "777")
  end

  test "PERSISTENCIA: reiniciar la aplicación conserva los datos en archivos de texto" do
    cod = u("RP")
    {:ok, _} = RecursosServer.registrar(%{codigo: cod, categoria: "agua", cantidad: 33, unidad: "l", ubicacion: "c_p", zona: "zt"}, "t")
    Application.stop(:emergencias)
    assert {:ok, _} = Application.ensure_all_started(:emergencias)
    assert {:ok, r} = RecursosServer.obtener(cod)
    assert r.cantidad == 33
    assert File.read!(Path.join(Emergencias.Almacen.directorio(), "recursos.txt")) =~ String.upcase(cod)
  end

  test "comandos: roles, autoregistro y validación de contraseña" do
    nombre = u("usr")
    assert {:ok, _, ciudadano} = Comandos.ejecutar("connect #{nombre} 1234 ciudadano zt", nil)
    assert {:error, msg, _} = Comandos.ejecutar("register_zone nueva Nueva alto", ciudadano)
    assert msg =~ "permiso"
    assert {:error, "Credenciales inválidas.", nil} = Comandos.ejecutar("connect #{nombre} mala", nil)
    assert {:ok, _, ^ciudadano} = Comandos.ejecutar("connect #{nombre} 1234", nil)
    assert {:ok, _, nil} = Comandos.ejecutar("disconnect", ciudadano)
    assert {:error, msg, nil} = Comandos.ejecutar("list_needs", nil)
    assert msg =~ "conectarse"
  end

  test "usuarios precargados: John y Daniel son administradores" do
    assert {:ok, msg, john} = Comandos.ejecutar("connect john john123", nil)
    assert john.tipo == :administrador and john.nombre == "John Medina"
    assert msg =~ "autenticado"
    assert {:ok, _, daniel} = Comandos.ejecutar("connect daniel daniel123", nil)
    assert daniel.nombre == "Daniel Montes"
    assert {:error, "Credenciales inválidas.", nil} = Comandos.ejecutar("connect john mala", nil)
    assert {:ok, _, _} = Comandos.ejecutar("register_zone zona_john \"Zona John\" alto", john)
  end

  test "comandos: flujo familiar y mascotas" do
    {:ok, _, c} = Comandos.ejecutar("connect #{u("coord")} 1 coordinador zt", nil)
    assert {:ok, _, _} = Comandos.ejecutar("report_person 555 \"Andrés Pérez\" zt localizada 30", c)
    assert {:error, _, _} = Comandos.ejecutar("report_person 555 Otro zt localizada", c)
    assert {:ok, out, _} = Comandos.ejecutar("find_person nombre=andres", c)
    assert out =~ "555"
    assert {:ok, _, _} = Comandos.ejecutar(~s|send_family_message 555 "Estoy bien"|, c)
    assert {:ok, out, _} = Comandos.ejecutar("list_family_messages 555", c)
    assert out =~ "Estoy bien"
    assert {:ok, _, _} = Comandos.ejecutar("report_pet lost gato Miel naranja pequeno zt 300 manchas blancas", c)
    assert {:ok, _, _} = Comandos.ejecutar("report_pet found gato desconocido naranja pequeno zt 301 manchas blancas", c)
    assert {:ok, out, _} = Comandos.ejecutar("match_pets", c)
    assert out =~ "similitud"
  end
end
