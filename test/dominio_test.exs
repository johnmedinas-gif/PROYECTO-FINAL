defmodule Emergencias.DominioTest do
  use ExUnit.Case, async: true
  alias Emergencias.{Recursion, Parser}
  alias Emergencias.Dominio.{Albergue, Mascota, Necesidad, Persona, Recurso, Zona}

  test "recursión: sumar, contar, agrupar y ordenar" do
    assert Recursion.sumar_por([1, 2, 3], &(&1 * 2)) == 12
    assert Recursion.contar_por(~w(a b a), & &1) == %{"a" => 2, "b" => 1}
    assert Recursion.sumar_por_clave([{:x, 1}, {:y, 2}, {:x, 3}], &elem(&1, 0), &elem(&1, 1)) == %{x: 4, y: 2}
    assert Recursion.ordenar([5, 3, 9, 1, 3], &(&1 <= &2)) == [1, 3, 3, 5, 9]
    assert Recursion.tomar_de_lotes([{"A", 10}, {"B", 10}], 15) == {[{"A", 10}, {"B", 5}], 0}
    assert Recursion.tomar_de_lotes([{"A", 10}], 15) == {[{"A", 10}], 5}
  end

  test "árbol de zonas: jerarquía, búsqueda y estadísticas recursivas" do
    {:ok, z} = Zona.nuevo(:zona, "Centro", "Centro", "critico", 100)
    {:ok, s} = Zona.nuevo(:sector, "s1", "Sector 1", "alto", "50")
    {:ok, p} = Zona.nuevo(:punto, "p1", "Punto 1", "medio", 10)
    {:ok, z} = Zona.registrar_hijo(z, [], s)
    {:ok, z} = Zona.registrar_hijo(z, ["s1"], p)

    assert Zona.total_afectados(z) == 160
    assert Zona.profundidad(z) == 3
    assert Zona.contar_nodos(z, :punto) == 1
    assert Zona.buscar(z, "p1").nombre == "Punto 1"
    assert Zona.nivel_maximo(z) == :critico
    assert {:error, :ya_existe} = Zona.registrar_hijo(z, [], s)
    {:ok, otro_punto} = Zona.nuevo(:punto, "p2", "Punto 2", "bajo", 0)
    assert {:error, :jerarquia_invalida} = Zona.registrar_hijo(z, [], otro_punto)
    assert {:error, :padre_no_existe} = Zona.registrar_hijo(z, ["nope"], otro_punto)
    assert {:error, :cantidad_negativa} = Zona.nuevo(:zona, "x", "x", "bajo", -1)
  end

  test "necesidad: validación, transiciones y orden por prioridad" do
    attrs = %{tipo: "agua", cantidad: "30", prioridad: "critica", zona: "centro", descripcion: "x"}
    assert {:ok, n} = Necesidad.crear("N001", attrs, "laura")
    assert {:error, :cantidad_negativa} = Necesidad.crear("N", %{attrs | cantidad: "-3"}, "l")
    assert {:error, :tipo_invalido} = Necesidad.crear("N", %{attrs | tipo: "oro"}, "l")
    assert {:error, {:transicion_invalida, :pendiente, :atendida}} = Necesidad.transicionar(n, "atendida", "l")
    {:ok, n} = Necesidad.transicionar(n, "cancelada", "l")
    assert {:error, :necesidad_cerrada} = Necesidad.validar_asignacion(n, "agua", 1)
    assert {:error, _} = Necesidad.transicionar(n, "cancelada", "l")

    {:ok, baja} = Necesidad.crear("N001", %{attrs | prioridad: "baja"}, "l")
    {:ok, alta} = Necesidad.crear("N002", %{attrs | prioridad: "critica"}, "l")
    assert Enum.map(Necesidad.ordenar_por_prioridad([baja, alta]), & &1.id) == ["N002", "N001"]
  end

  test "recurso no admite cantidades negativas ni salidas excesivas" do
    {:ok, r} = Recurso.crear(%{codigo: "r1", categoria: "agua", cantidad: 10, unidad: "l", ubicacion: "c1", zona: "z"})
    assert {:error, :cantidad_insuficiente} = Recurso.salida(r, 11)
    assert {:error, :cantidad_negativa} = Recurso.entrada(r, -1)
    {:ok, r} = Recurso.salida(r, 8)
    assert Recurso.critico?(r)
  end

  test "persona: estados válidos" do
    {:ok, p} = Persona.crear("1", "Ana", 20, "z", "reportada", "u")
    assert {:ok, p} = Persona.cambiar_estado(p, "localizada", "u")
    assert length(p.historial) == 2
    {:ok, p} = Persona.cambiar_estado(p, "reunificada", "u")
    assert {:error, {:transicion_invalida, :reunificada, :localizada}} = Persona.cambiar_estado(p, "localizada", "u")
  end

  test "albergue no supera su capacidad" do
    {:ok, a} = Albergue.nuevo("a1", "A", "z", 1)
    {:ok, a} = Albergue.ingresar(a, "1")
    assert {:error, :sin_cupo} = Albergue.ingresar(a, "2")
    assert {:error, :ya_ingresado} = Albergue.ingresar(a, "1")
    assert Albergue.porcentaje(a) == 100.0
  end

  test "mascotas: puntaje de similitud" do
    base = %{tipo: "lost", especie: "perro", nombre: "Luna", color: "negra", tamano: "mediana", zona: "n", contacto: "1", caracteristicas: "collar rojo"}
    {:ok, a} = Mascota.crear("M001", base, "u")
    {:ok, b} = Mascota.crear("M002", %{base | tipo: "found", nombre: "desconocido"}, "u")
    {:ok, c} = Mascota.crear("M003", %{base | tipo: "found", especie: "gato"}, "u")
    assert Mascota.puntaje(a, b) >= Mascota.umbral()
    assert Mascota.puntaje(a, c) == 0
  end

  test "parser respeta comillas" do
    assert Parser.tokenizar(~s|send 123 "hola mundo" fin|) == ["send", "123", "hola mundo", "fin"]
  end
end
