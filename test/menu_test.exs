defmodule Emergencias.MenuTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias Emergencias.{Menu, ZonasServer}

  defp u(n), do: "#{n}#{System.unique_integer([:positive])}"

  test "el coordinador registra una zona desde el menú" do
    user = u("menu_c")
    zona = u("zmenu")

    entrada =
      ["1", user, "1234", "3", "zcentro", "", "1", "1", zona, "Zona Menu", "1", "", "", "0", "0", "0"]
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    salida = capture_io([input: entrada], fn -> Menu.iniciar() end)
    assert salida =~ "Zona registrada: #{zona}"
    assert salida =~ "usuario registrado"
    assert ZonasServer.existe?(zona)
  end

  test "el ciudadano no ve opciones que su rol no permite" do
    entrada = ["1", u("menu_ciu"), "1234", "", "", "", "1", "0", "0", "0"] |> Enum.join("\n") |> Kernel.<>("\n")
    salida = capture_io([input: entrada], fn -> Menu.iniciar() end)
    assert salida =~ "Listar zonas"
    refute salida =~ "Registrar zona"
    refute salida =~ "Resumen y reportes"
  end

  test "si la zona no existe, el menú explica cómo registrarla y vuelve a preguntar" do
    zona = u("zok")
    {:ok, _} = ZonasServer.registrar_zona(zona, "Zona OK", "alto")
    # ciudadano > Personas (sección 4 de su menú) > Registrar persona: zona inexistente, luego válida
    entrada =
      ["1", u("menu_z"), "1234", "", "", "", "4", "1", "999", "Ana Perez", "zona_que_no_existe", zona, "1", "", "", "0", "0", "0"]
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    salida = capture_io([input: entrada], fn -> Menu.iniciar() end)
    assert salida =~ "no está registrada"
    assert salida =~ "Zonas afectadas > Registrar zona"
    assert salida =~ "Persona registrada"
  end

  test "un usuario existente solo da usuario y contraseña (no se pide tipo ni zona)" do
    entrada = ["1", "john", "john123", "0", "0"] |> Enum.join("\n") |> Kernel.<>("\n")
    salida = capture_io([input: entrada], fn -> Menu.iniciar() end)
    assert salida =~ "usuario autenticado"
    assert salida =~ "John Medina (administrador)"
    refute salida =~ "Tipo de usuario"
    refute salida =~ "Zona principal"
  end

  test "contraseña incorrecta de un usuario existente" do
    entrada = ["1", "daniel", "mala", "0"] |> Enum.join("\n") |> Kernel.<>("\n")
    salida = capture_io([input: entrada], fn -> Menu.iniciar() end)
    assert salida =~ "Credenciales inválidas"
    refute salida =~ "Tipo de usuario"
  end

  test "termina sin errores cuando se acaba la entrada" do
    assert capture_io([input: "1\nsolo_usuario\nclave\n"], fn -> Menu.iniciar() end) =~ "Hasta pronto"
  end
end
