defmodule Emergencias.Comandos do
  @moduledoc """
  Interpreta una línea de comando en nombre de un usuario (o de nadie, antes de `connect`).
  Devuelve `{:ok | :error, texto, usuario_actual}`. Es la capa de entrada: valida permisos
  según el tipo de usuario, delega en los servidores y registra la actividad.
  """
  alias Emergencias.{Albergues, Fachada, Formato, MascotasServer, NecesidadesServer, Parser, PersonasServer, RecursosServer, UsuariosServer, ZonasServer}
  alias Emergencias.{Errores, Util}
  alias Emergencias.Dominio.Permisos

  def ejecutar(linea, usuario \\ nil) do
    case Parser.tokenizar(linea) do
      [] -> {:ok, "", usuario}
      [cmd | args] -> despachar(String.downcase(cmd), args, usuario)
    end
  end

  defp despachar("connect", [user, pass | resto], _actual) do
    {tipo, resto} = sacar(resto, "ciudadano")
    {zona, resto} = sacar(resto, "general")
    {nombre, _} = sacar(resto, user)

    case UsuariosServer.conectar(user, pass, tipo, zona, nombre) do
      {:ok, u, como} ->
        UsuariosServer.registrar_actividad(u.username, "connect (#{como})")
        {:ok, "Bienvenido #{u.nombre} (#{u.tipo}, zona #{u.zona}) - usuario #{como}.", u}

      {:error, razon} ->
        {:error, Errores.mensaje(razon), nil}
    end
  end

  defp despachar("connect", _, actual), do: {:error, Errores.mensaje({:uso, Formato.uso("connect")}), actual}
  defp despachar("help", _, actual), do: {:ok, Formato.ayuda(), actual}

  defp despachar(cmd, _args, nil) do
    if Permisos.existe?(cmd),
      do: {:error, "Debe conectarse primero: connect usuario contraseña [tipo] [zona]", nil},
      else: {:error, "Comando desconocido: #{cmd}. Use help.", nil}
  end

  defp despachar("disconnect", _, usuario) do
    UsuariosServer.registrar_actividad(usuario.username, "disconnect")
    UsuariosServer.desconectar(usuario.username)
    {:ok, "Hasta pronto, #{usuario.nombre}.", nil}
  end

  defp despachar(cmd, args, usuario) do
    cond do
      not Permisos.existe?(cmd) ->
        {:error, "Comando desconocido: #{cmd}. Use help.", usuario}

      not Permisos.permitido?(usuario.tipo, cmd) ->
        {:error, Errores.mensaje(:sin_permiso), usuario}

      true ->
        resultado = comando(cmd, args, usuario)
        UsuariosServer.registrar_actividad(usuario.username, "#{cmd} #{Enum.join(args, " ")} -> #{elem(resultado, 0)}")

        case resultado do
          {:ok, texto} -> {:ok, texto, usuario}
          {:error, razon} -> {:error, Errores.mensaje(razon), usuario}
        end
    end
  end

  defp sacar([], defecto), do: {defecto, []}
  defp sacar([x | resto], _), do: {x, resto}

  # ---------------------------------------------------------------- zonas
  defp comando("register_zone", [codigo, nombre, nivel | opc], _u) do
    with {:ok, z} <- ZonasServer.registrar_zona(codigo, nombre, nivel, opcional(opc, 0)),
         do: {:ok, "Zona registrada: #{z.codigo} (#{z.nivel})."}
  end

  defp comando("register_sector", [zona, codigo, nombre, nivel | opc], _u) do
    with {:ok, s} <- ZonasServer.registrar_sector(zona, codigo, nombre, nivel, opcional(opc, 0)),
         do: {:ok, "Sector registrado: #{s.codigo} en #{Util.codigo(zona)}."}
  end

  defp comando("register_point", [zona, sector, codigo, nombre, nivel | opc], _u) do
    with {:ok, p} <- ZonasServer.registrar_punto(zona, sector, codigo, nombre, nivel, opcional(opc, 0)),
         do: {:ok, "Punto de atención registrado: #{p.codigo} en #{Util.codigo(sector)}."}
  end

  defp comando("list_zones", [], _u), do: {:ok, Formato.lista(ZonasServer.listar(), "No hay zonas registradas.", &Formato.zona/1)}

  defp comando("zone_status", [zona], _u) do
    with {:ok, e} <- Fachada.estado_zona(zona) do
      s = e.estadisticas

      {:ok,
       """
       Zona #{e.zona.codigo} - #{e.zona.nombre}
       #{Formato.arbol(e.zona)}
       Estadísticas: #{s.afectados} afectados | #{s.sectores} sectores | #{s.puntos} puntos | profundidad #{s.profundidad} | niveles: #{Formato.conteo(s.por_nivel)}
       Necesidades (#{length(e.necesidades)}): #{Formato.conteo(Emergencias.Recursion.contar_por(e.necesidades, & &1.estado))}
       Recursos: #{length(e.recursos)} lotes | Albergues: #{length(e.albergues)} | Personas: #{length(e.personas)} | Reportes de mascotas: #{length(e.mascotas)}
       """
       |> String.trim_trailing()}
    end
  end

  # ---------------------------------------------------------------- necesidades
  defp comando("register_need", [tipo, cantidad, prioridad, zona | descripcion], u) when descripcion != [] do
    attrs = %{tipo: tipo, cantidad: cantidad, prioridad: prioridad, zona: zona, descripcion: Enum.join(descripcion, " ")}
    with {:ok, n} <- NecesidadesServer.registrar(attrs, u.username), do: {:ok, "Necesidad registrada: #{Formato.necesidad(n)}"}
  end

  defp comando("list_needs", args, _u) do
    with {:ok, _, filtros} <- Parser.filtros(args, [:zona, :tipo, :prioridad, :estado]),
         do: {:ok, Formato.lista(NecesidadesServer.listar(filtros), "No hay necesidades que coincidan.", &Formato.necesidad/1)}
  end

  defp comando("pending_needs", [], _u),
    do: {:ok, Formato.lista(NecesidadesServer.pendientes(), "No hay necesidades pendientes.", &Formato.necesidad/1)}

  defp comando("assign_resource", [id, categoria, cantidad], u) do
    with {:ok, n, tomados} <- NecesidadesServer.asignar(id, categoria, cantidad, u.username) do
      origen = Enum.map_join(tomados, ", ", fn {cod, c} -> "#{cod}: #{c}" end)
      {:ok, "Asignado a #{n.id} (#{origen}). Estado: #{n.estado}, cubierto #{n.asignado}/#{n.cantidad}."}
    end
  end

  defp comando("attend_need", [id], u), do: cambiar_necesidad(id, "en_atencion", u)
  defp comando("close_need", [id], u), do: cambiar_necesidad(id, "atendida", u)
  defp comando("cancel_need", [id], u), do: cambiar_necesidad(id, "cancelada", u)

  # ---------------------------------------------------------------- recursos
  defp comando("register_resource", [codigo, categoria, cantidad, unidad, ubicacion | opc], u) do
    attrs = %{codigo: codigo, categoria: categoria, cantidad: cantidad, unidad: unidad, ubicacion: ubicacion, zona: opcional(opc, u.zona)}
    with {:ok, r} <- RecursosServer.registrar(attrs, u.username), do: {:ok, "Recurso registrado: #{Formato.recurso(r)}"}
  end

  defp comando("resource_in", [codigo, n], u),
    do: with({:ok, r} <- RecursosServer.entrada(codigo, n, u.username), do: {:ok, "Entrada registrada: #{Formato.recurso(r)}"})

  defp comando("resource_out", [codigo, n], u),
    do: with({:ok, r} <- RecursosServer.salida(codigo, n, u.username), do: {:ok, "Salida registrada: #{Formato.recurso(r)}"})

  defp comando("list_resources", args, _u) do
    with {:ok, _, filtros} <- Parser.filtros(args, [:categoria, :zona, :ubicacion]),
         do: {:ok, Formato.lista(RecursosServer.listar(filtros), "No hay recursos que coincidan.", &Formato.recurso/1)}
  end

  defp comando("transfer_resource", [codigo, origen, destino, n], u) do
    with {:ok, o, d} <- RecursosServer.transferir(codigo, origen, destino, n, u.username),
         do: {:ok, "Transferencia realizada.\n  origen:  #{Formato.recurso(o)}\n  destino: #{Formato.recurso(d)}"}
  end

  defp comando("critical_resources", [], _u),
    do: {:ok, Formato.lista(RecursosServer.criticos(), "No hay recursos en nivel crítico.", &Formato.recurso/1)}

  defp comando("movements", args, _u),
    do: {:ok, Formato.lista(RecursosServer.movimientos(List.first(args)), "Sin movimientos.", &Formato.movimiento/1)}

  # ---------------------------------------------------------------- personas y mensajes
  defp comando("report_person", [doc, nombre, zona, estado | opc], u) do
    with {:ok, p} <- PersonasServer.reportar(doc, nombre, zona, estado, opcional(opc, nil), u.username),
         do: {:ok, "Persona registrada: #{Formato.persona(p)}"}
  end

  defp comando("update_person", [doc, estado], u),
    do: with({:ok, p} <- PersonasServer.cambiar_estado(doc, estado, u.username), do: {:ok, "Persona actualizada: #{Formato.persona(p)}"})

  defp comando("find_person", args, _u) do
    with {:ok, pos, filtros} <- Parser.filtros(args, [:nombre, :documento, :zona, :estado]) do
      filtros = if pos != [], do: Map.put(filtros, :documento, hd(pos)), else: filtros
      {:ok, Formato.lista(PersonasServer.listar(filtros), "No se encontraron personas.", &Formato.persona/1)}
    end
  end

  defp comando("send_family_message", [doc | contenido], u) when contenido != [],
    do: with({:ok, m} <- PersonasServer.enviar_mensaje(u.username, doc, Enum.join(contenido, " ")), do: {:ok, "Mensaje guardado: #{m.id}"})

  defp comando("list_family_messages", [doc], _u),
    do: {:ok, Formato.lista(PersonasServer.mensajes(doc), "No hay mensajes para #{Util.id(doc)}.", &Formato.mensaje/1)}

  defp comando("deliver_message", [id], _u),
    do: with({:ok, m} <- PersonasServer.entregar_mensaje(id), do: {:ok, "Mensaje #{m.id} marcado como entregado."})

  # ---------------------------------------------------------------- mascotas
  defp comando("report_pet", [tipo, especie, nombre, color, tamano, zona, contacto | extra], u) do
    attrs = %{tipo: tipo, especie: especie, nombre: nombre, color: color, tamano: tamano, zona: zona, contacto: contacto, caracteristicas: Enum.join(extra, " ")}
    with {:ok, m} <- MascotasServer.reportar(attrs, u.username), do: {:ok, "Reporte registrado: #{Formato.mascota(m)}"}
  end

  defp comando("list_pets", args, _u) do
    with {:ok, _, filtros} <- Parser.filtros(args, [:especie, :zona, :estado, :tipo]),
         do: {:ok, Formato.lista(MascotasServer.listar(filtros), "No hay reportes que coincidan.", &Formato.mascota/1)}
  end

  defp comando("match_pets", [], _u) do
    pares = MascotasServer.buscar_coincidencias()

    {:ok,
     Formato.lista(pares, "No se encontraron coincidencias (umbral #{Emergencias.Dominio.Mascota.umbral()}/100).", fn {p, e, s} ->
       "#{p} (perdida) ~ #{e} (encontrada) | similitud #{s}/100"
     end)}
  end

  defp comando("confirm_match", [perdida, encontrada], u) do
    with {:ok, p, e} <- MascotasServer.confirmar(perdida, encontrada, u.username),
         do: {:ok, "Coincidencia confirmada: #{p.id} ↔ #{e.id}. Ambos reportes quedaron resueltos."}
  end

  # ---------------------------------------------------------------- albergues
  defp comando("register_shelter", [codigo, nombre, zona, capacidad], _u) do
    with {:ok, a} <- Albergues.registrar(codigo, nombre, zona, capacidad), do: {:ok, "Albergue registrado: #{Formato.albergue(a)}"}
  end

  defp comando("check_shelter", [codigo], _u), do: with({:ok, a} <- Albergues.consultar(codigo), do: {:ok, shelter_detalle(a)})
  defp comando("list_shelters", [], _u), do: {:ok, Formato.lista(Albergues.listar(), "No hay albergues.", &Formato.albergue/1)}

  defp comando("link_shelter", [codigo, tipo, id], _u) do
    with {:ok, tipo} <- Util.elegir(tipo(tipo), [:necesidad, :recurso], {:uso, Formato.uso("link_shelter")}),
         {:ok, a} <- Albergues.vincular(codigo, tipo, id),
         do: {:ok, "Vinculado #{Util.id(id)} al albergue #{a.codigo}."}
  end

  defp comando("register_entry", [codigo, doc], u),
    do: with({:ok, a} <- Fachada.ingresar_albergue(codigo, doc, u.username), do: {:ok, "Ingreso registrado. #{Formato.albergue(a)}"})

  defp comando("register_exit", [codigo, doc], u),
    do: with({:ok, a} <- Fachada.salir_albergue(codigo, doc, u.username), do: {:ok, "Salida registrada. #{Formato.albergue(a)}"})

  defp comando("shelter_report", [], _u),
    do: {:ok, "Albergues con mayor ocupación:\n" <> Formato.lista(Albergues.mas_ocupados(), "No hay albergues.", &Formato.albergue/1)}

  # ---------------------------------------------------------------- global
  defp comando("summary", [], _u), do: {:ok, Formato.resumen(Fachada.resumen())}

  defp comando("activity", args, _u) do
    lista = UsuariosServer.actividad(List.first(args))
    {:ok, Formato.lista(lista, "Sin actividad.", &"#{&1.fecha} | #{&1.usuario} | #{&1.accion}")}
  end

  defp comando(cmd, _args, _u), do: {:error, {:uso, Formato.uso(cmd)}}

  defp cambiar_necesidad(id, estado, u) do
    with {:ok, n} <- NecesidadesServer.transicionar(id, estado, u.username), do: {:ok, "Necesidad actualizada: #{Formato.necesidad(n)}"}
  end

  defp shelter_detalle(a) do
    alias Emergencias.Dominio.Albergue

    Formato.albergue(a) <>
      "\n  personas: #{inspect(MapSet.to_list(a.personas))}\n  necesidades: #{inspect(MapSet.to_list(a.necesidades))}\n  recursos: #{inspect(MapSet.to_list(a.recursos))}" <>
      "\n  cupos disponibles: #{Albergue.cupos(a)}"
  end

  defp tipo(t), do: if(Util.codigo(t) in ["need", "necesidad"], do: "necesidad", else: if(Util.codigo(t) in ["resource", "recurso"], do: "recurso", else: t))

  defp opcional([x | _], _), do: x
  defp opcional([], defecto), do: defecto
end
