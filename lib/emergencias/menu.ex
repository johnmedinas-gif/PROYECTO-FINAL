defmodule Emergencias.Menu do
  @moduledoc """
  Menú interactivo en consola. No tiene lógica propia: pide los datos paso a paso, arma
  la línea de comando equivalente y la ejecuta con `Comandos.ejecutar/2`, por lo que los
  permisos por rol, las validaciones y la bitácora son los mismos que en la consola de comandos.
  Cada usuario solo ve las opciones que su rol permite.

  Campos de cada opción: `{:req, p}` obligatorio (Enter vacío cancela), `{:def, p, valor}` con valor
  por defecto, `{:opt, p}` opcional, `{:elegir, p, opciones[, defecto]}`, `{:zona, p}` /
  `{:zona_opt, p}` (muestra las zonas registradas) y `{:filtro, clave, p}` (Enter = sin filtro).
  """
  alias Emergencias.Dominio.Permisos
  alias Emergencias.{Comandos, UsuariosServer, ZonasServer}

  @tipos_usuario ~w(ciudadano voluntario coordinador administrador)
  @niveles ~w(critico alto medio bajo)
  @tipos_necesidad ~w(agua alimentos medicamentos primeros_auxilios refugio transporte rescate otra)
  @prioridades ~w(critica alta media baja)
  @estados_persona ~w(sin_informacion reportada localizada trasladada en_albergue reunificada)
  @estados_alta ~w(sin_informacion reportada localizada trasladada en_albergue)
  @tamanos ~w(pequeno mediano grande)

  @secciones [
    {"Zonas afectadas",
     [
       {"Registrar zona", "register_zone", [{:req, "Código de la zona"}, {:req, "Nombre"}, {:elegir, "Nivel de afectación", @niveles}, {:def, "Personas afectadas estimadas", "0"}]},
       {"Registrar sector", "register_sector", [{:zona, "Zona"}, {:req, "Código del sector"}, {:req, "Nombre"}, {:elegir, "Nivel de afectación", @niveles}, {:def, "Personas afectadas estimadas", "0"}]},
       {"Registrar punto de atención", "register_point", [{:zona, "Zona"}, {:req, "Código del sector"}, {:req, "Código del punto"}, {:req, "Nombre"}, {:elegir, "Nivel de afectación", @niveles}, {:def, "Personas afectadas estimadas", "0"}]},
       {"Listar zonas", "list_zones", []},
       {"Estado general de una zona", "zone_status", [{:zona, "Zona"}]}
     ]},
    {"Necesidades",
     [
       {"Registrar necesidad", "register_need", [{:elegir, "Tipo de necesidad", @tipos_necesidad}, {:req, "Cantidad requerida"}, {:elegir, "Prioridad", @prioridades}, {:zona, "Zona"}, {:req, "Descripción"}]},
       {"Listar necesidades (con filtros)", "list_needs", [{:filtro, "zona", "Filtrar por zona"}, {:filtro, "tipo", "Filtrar por tipo"}, {:filtro, "prioridad", "Filtrar por prioridad"}, {:filtro, "estado", "Filtrar por estado"}]},
       {"Necesidades pendientes (por prioridad)", "pending_needs", []},
       {"Asignar recursos a una necesidad", "assign_resource", [{:req, "ID de la necesidad (ej. N001)"}, {:elegir, "Categoría del recurso", @tipos_necesidad}, {:req, "Cantidad a asignar"}]},
       {"Poner una necesidad en atención", "attend_need", [{:req, "ID de la necesidad"}]},
       {"Marcar necesidad como atendida", "close_need", [{:req, "ID de la necesidad"}]},
       {"Cancelar una necesidad", "cancel_need", [{:req, "ID de la necesidad"}]}
     ]},
    {"Recursos y centros de apoyo",
     [
       {"Registrar recurso", "register_resource", [{:req, "Código (ej. R001)"}, {:req, "Categoría (agua, alimentos, medicamentos...)"}, {:req, "Cantidad inicial"}, {:req, "Unidad (litros, kg, unidades...)"}, {:req, "Centro de apoyo / ubicación"}, {:zona_opt, "Zona (Enter = su zona)"}]},
       {"Listar recursos (con filtros)", "list_resources", [{:filtro, "categoria", "Filtrar por categoría"}, {:filtro, "zona", "Filtrar por zona"}, {:filtro, "ubicacion", "Filtrar por ubicación"}]},
       {"Registrar entrada de inventario", "resource_in", [{:req, "Código del recurso"}, {:req, "Cantidad que ingresa"}]},
       {"Registrar salida de inventario", "resource_out", [{:req, "Código del recurso"}, {:req, "Cantidad que sale"}]},
       {"Transferir entre centros de apoyo", "transfer_resource", [{:req, "Código del recurso"}, {:req, "Centro de origen"}, {:req, "Centro de destino"}, {:req, "Cantidad"}]},
       {"Recursos en nivel crítico", "critical_resources", []},
       {"Historial de movimientos", "movements", [{:opt, "Código del recurso"}]}
     ]},
    {"Personas y mensajes familiares",
     [
       {"Registrar persona afectada", "report_person", [{:req, "Documento"}, {:req, "Nombre completo"}, {:zona, "Zona"}, {:elegir, "Estado", @estados_alta}, {:opt, "Edad"}]},
       {"Cambiar estado de una persona", "update_person", [{:req, "Documento"}, {:elegir, "Nuevo estado", @estados_persona}]},
       {"Buscar personas", "find_person", [{:filtro, "documento", "Documento"}, {:filtro, "nombre", "Nombre (parcial)"}, {:filtro, "zona", "Zona"}, {:filtro, "estado", "Estado"}]},
       {"Enviar mensaje a un familiar", "send_family_message", [{:req, "Documento del destinatario"}, {:req, "Mensaje"}]},
       {"Ver mensajes de una persona", "list_family_messages", [{:req, "Documento"}]},
       {"Marcar mensaje como entregado", "deliver_message", [{:req, "ID del mensaje (ej. MSG001)"}]}
     ]},
    {"Mascotas perdidas y encontradas",
     [
       {"Reportar mascota", "report_pet", [{:elegir, "Tipo de reporte", ~w(perdida encontrada)}, {:req, "Especie (perro, gato...)"}, {:req, "Nombre (escriba 'desconocido' si no se sabe)"}, {:req, "Color"}, {:elegir, "Tamaño", @tamanos}, {:zona, "Zona"}, {:req, "Contacto (teléfono)"}, {:opt, "Características (collar, manchas...)"}]},
       {"Listar reportes (con filtros)", "list_pets", [{:filtro, "especie", "Filtrar por especie"}, {:filtro, "zona", "Filtrar por zona"}, {:filtro, "estado", "Filtrar por estado"}, {:filtro, "tipo", "Filtrar por tipo (perdida/encontrada)"}]},
       {"Buscar posibles coincidencias", "match_pets", []},
       {"Confirmar coincidencia y cerrar reportes", "confirm_match", [{:req, "ID del reporte de mascota perdida (ej. M001)"}, {:req, "ID del reporte de mascota encontrada"}]}
     ]},
    {"Albergues",
     [
       {"Registrar albergue", "register_shelter", [{:req, "Código (ej. A01)"}, {:req, "Nombre"}, {:zona, "Zona"}, {:req, "Capacidad máxima"}]},
       {"Consultar un albergue", "check_shelter", [{:req, "Código del albergue"}]},
       {"Listar albergues", "list_shelters", []},
       {"Registrar ingreso de una persona", "register_entry", [{:req, "Código del albergue"}, {:req, "Documento de la persona"}]},
       {"Registrar salida de una persona", "register_exit", [{:req, "Código del albergue"}, {:req, "Documento de la persona"}]},
       {"Asociar necesidad o recurso al albergue", "link_shelter", [{:req, "Código del albergue"}, {:elegir, "¿Qué desea asociar?", ~w(need resource)}, {:req, "ID de la necesidad o del recurso"}]},
       {"Albergues con mayor ocupación", "shelter_report", []}
     ]},
    {"Resumen y reportes",
     [
       {"Resumen global", "summary", []},
       {"Recursos críticos", "critical_resources", []},
       {"Necesidades pendientes", "pending_needs", []},
       {"Albergues con mayor ocupación", "shelter_report", []},
       {"Actividad de usuarios", "activity", [{:opt, "Usuario (Enter = todos)"}]}
     ]}
  ]

  def iniciar do
    IO.puts("""

    ==============================================================
      Coordinación de emergencias · terremoto
      Menú interactivo (Enter vacío en un dato obligatorio cancela)
    ==============================================================
    """)

    try do
      inicio()
    catch
      :throw, :fin_de_entrada -> IO.puts("\nHasta pronto.")
    end

    :ok
  end

  # ---------------------------------------------------------------- sin sesión
  defp inicio do
    IO.puts("\n--- Inicio ---\n  1. Conectarse o registrarse\n  0. Salir")

    case opcion(1) do
      0 -> IO.puts("Hasta pronto.")
      1 -> conectar()
      :invalida -> IO.puts("Opción no válida.") && inicio()
    end
  end

  defp conectar do
    case pedir([{:req, "Usuario"}, {:req, "Contraseña"}]) do
      :cancelado ->
        IO.puts("Operación cancelada.")
        inicio()

      {:ok, [usuario, clave]} ->
        # Si el usuario ya existe basta con la contraseña; solo los usuarios nuevos completan su registro.
        extras =
          case UsuariosServer.obtener(String.trim(usuario, "\"")) do
            {:ok, _} ->
              {:ok, []}

            {:error, _} ->
              IO.puts("\nUsuario nuevo: se registrará automáticamente. Complete sus datos.")
              pedir([{:elegir, "Tipo de usuario", @tipos_usuario, "ciudadano"}, {:def, "Zona principal", "general"}, {:opt, "Nombre completo"}])
          end

        case extras do
          :cancelado ->
            IO.puts("Operación cancelada.")
            inicio()

          {:ok, resto} ->
            {estado, texto, sesion} = Comandos.ejecutar(Enum.join(["connect", usuario, clave | resto], " "), nil)
            mostrar(estado, texto)
            if sesion, do: menu_principal(sesion), else: inicio()
        end
    end
  end

  # ---------------------------------------------------------------- con sesión
  defp menu_principal(usuario) do
    secciones = secciones_visibles(usuario)
    IO.puts("\n=== MENÚ PRINCIPAL · #{usuario.nombre} (#{usuario.tipo}) · zona #{usuario.zona} ===")
    secciones |> Enum.with_index(1) |> Enum.each(fn {{nombre, _}, i} -> IO.puts("  #{i}. #{nombre}") end)
    IO.puts("  0. Cerrar sesión")

    case opcion(length(secciones)) do
      0 ->
        {_, texto, _} = Comandos.ejecutar("disconnect", usuario)
        IO.puts(texto)
        inicio()

      :invalida ->
        IO.puts("Opción no válida.")
        menu_principal(usuario)

      n ->
        menu_seccion(Enum.at(secciones, n - 1), usuario)
        menu_principal(usuario)
    end
  end

  defp menu_seccion({nombre, items} = seccion, usuario) do
    IO.puts("\n--- #{nombre} ---")
    items |> Enum.with_index(1) |> Enum.each(fn {{etiqueta, _, _}, i} -> IO.puts("  #{i}. #{etiqueta}") end)
    IO.puts("  0. Volver")

    case opcion(length(items)) do
      0 ->
        :ok

      :invalida ->
        IO.puts("Opción no válida.")
        menu_seccion(seccion, usuario)

      n ->
        {_, comando, campos} = Enum.at(items, n - 1)
        ejecutar_item(comando, campos, usuario)
        menu_seccion(seccion, usuario)
    end
  end

  defp ejecutar_item(comando, campos, usuario) do
    case pedir(campos) do
      {:ok, tokens} ->
        {estado, texto, _} = Comandos.ejecutar(Enum.join([comando | tokens], " "), usuario)
        mostrar(estado, texto)

      :cancelado ->
        IO.puts("Operación cancelada.")
    end

    leer("\nEnter para continuar...")
  end

  # Solo se muestran las secciones y opciones que el rol del usuario puede ejecutar.
  defp secciones_visibles(usuario) do
    @secciones
    |> Enum.map(fn {nombre, items} -> {nombre, Enum.filter(items, fn {_, cmd, _} -> Permisos.permitido?(usuario.tipo, cmd) end)} end)
    |> Enum.reject(fn {_, items} -> items == [] end)
  end

  # ---------------------------------------------------------------- captura de datos
  # Recursión sobre la lista de campos: cada paso pide un dato y continúa con el resto.
  defp pedir(campos), do: pedir(campos, [])
  defp pedir([], acc), do: {:ok, Enum.reverse(acc)}

  defp pedir([campo | resto], acc) do
    case pedir_campo(campo) do
      :cancelar -> :cancelado
      :omitir -> pedir(resto, acc)
      {:ok, valor} -> pedir(resto, [valor | acc])
    end
  end

  defp pedir_campo({:req, p}), do: requerido(leer("#{p}: "))

  defp pedir_campo({:def, p, defecto}) do
    case leer("#{p} [#{defecto}]: ") do
      "" -> {:ok, citar(defecto)}
      v -> {:ok, citar(v)}
    end
  end

  defp pedir_campo({:opt, p}), do: opcional(leer("#{p} (opcional): "))
  defp pedir_campo({:zona, p}), do: pedir_zona(p, false)
  defp pedir_campo({:zona_opt, p}), do: pedir_zona(p, true)

  defp pedir_campo({:filtro, clave, p}) do
    case leer("#{p} (Enter = sin filtro): ") do
      "" -> :omitir
      v -> {:ok, "#{clave}=#{citar(v)}"}
    end
  end

  defp pedir_campo({:elegir, p, opciones}), do: elegir(p, opciones, nil)
  defp pedir_campo({:elegir, p, opciones, defecto}), do: elegir(p, opciones, defecto)

  defp elegir(p, opciones, defecto) do
    IO.puts("#{p}:")
    opciones |> Enum.with_index(1) |> Enum.each(fn {o, i} -> IO.puts("  #{i}. #{o}") end)
    sufijo = if defecto, do: " [Enter = #{defecto}]", else: ""

    case leer("Elija (número o nombre)#{sufijo}: ") do
      "" when defecto != nil -> {:ok, defecto}
      "" -> :cancelar
      v ->
        case resolver(v, opciones) do
          nil ->
            IO.puts("Opción no válida, intente de nuevo.")
            elegir(p, opciones, defecto)

          opcion ->
            {:ok, opcion}
        end
    end
  end

  defp resolver(texto, opciones) do
    case Integer.parse(texto) do
      {n, ""} when n >= 1 and n <= length(opciones) -> Enum.at(opciones, n - 1)
      _ -> Enum.find(opciones, &(String.downcase(&1) == String.downcase(texto)))
    end
  end

  defp requerido(""), do: :cancelar
  defp requerido(v), do: {:ok, citar(v)}
  defp opcional(""), do: :omitir
  defp opcional(v), do: {:ok, citar(v)}

  # Valida que la zona exista ANTES de continuar; si no, explica cómo registrarla y vuelve a preguntar.
  defp pedir_zona(p, opcional?) do
    mostrar_zonas()

    case leer("#{p}#{if opcional?, do: " (opcional)", else: ""}: ") do
      "" ->
        if opcional?, do: :omitir, else: :cancelar

      v ->
        if ZonasServer.existe?(v) do
          {:ok, citar(v)}
        else
          IO.puts("\n✗ La zona '#{v}' no está registrada. Escriba una de la lista, o pulse Enter para cancelar y")
          IO.puts("  registrarla primero en: Menú principal > Zonas afectadas > Registrar zona (coordinador o administrador).\n")
          pedir_zona(p, opcional?)
        end
    end
  end

  defp mostrar_zonas do
    case ZonasServer.listar() do
      [] -> IO.puts("(No hay zonas registradas todavía: use 'Zonas afectadas > Registrar zona')")
      zonas -> IO.puts("Zonas registradas: " <> Enum.map_join(zonas, ", ", & &1.codigo))
    end
  end

  # Los valores con espacios se envuelven en comillas para que el Parser los trate como uno solo.
  defp citar(v), do: if(String.contains?(v, [" ", "\t"]), do: ~s("#{String.replace(v, "\"", "'")}"), else: v)

  defp opcion(max) do
    case Integer.parse(leer("Opción: ")) do
      {n, ""} when n >= 0 and n <= max -> n
      _ -> :invalida
    end
  end

  defp mostrar(:ok, texto), do: IO.puts("\n✓ " <> texto)
  defp mostrar(:error, texto), do: IO.puts("\n✗ " <> texto)

  defp leer(prompt) do
    case IO.gets(prompt) do
      v when is_binary(v) -> String.trim(v)
      _ -> throw(:fin_de_entrada)
    end
  end
end
