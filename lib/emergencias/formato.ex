defmodule Emergencias.Formato do
  @moduledoc "Presentación en texto de los registros."
  alias Emergencias.Dominio.{Albergue, Zona}

  @ayuda [
    {"connect", "connect usuario contraseña [tipo] [zona] [nombre_completo]"},
    {"disconnect", "disconnect"},
    {"register_zone", "register_zone codigo nombre nivel [afectados]"},
    {"register_sector", "register_sector zona codigo nombre nivel [afectados]"},
    {"register_point", "register_point zona sector codigo nombre nivel [afectados]"},
    {"list_zones", "list_zones"},
    {"zone_status", "zone_status zona"},
    {"register_need", "register_need tipo cantidad prioridad zona descripcion"},
    {"list_needs", "list_needs [zona=..] [tipo=..] [prioridad=..] [estado=..]"},
    {"pending_needs", "pending_needs"},
    {"assign_resource", "assign_resource N001 categoria cantidad"},
    {"attend_need", "attend_need N001"},
    {"close_need", "close_need N001"},
    {"cancel_need", "cancel_need N001"},
    {"register_resource", "register_resource codigo categoria cantidad unidad ubicacion [zona]"},
    {"resource_in", "resource_in codigo cantidad"},
    {"resource_out", "resource_out codigo cantidad"},
    {"list_resources", "list_resources [categoria=..] [zona=..] [ubicacion=..]"},
    {"transfer_resource", "transfer_resource codigo origen destino cantidad"},
    {"critical_resources", "critical_resources"},
    {"movements", "movements [codigo]"},
    {"report_person", "report_person documento nombre zona estado [edad]"},
    {"update_person", "update_person documento estado"},
    {"find_person", "find_person documento | find_person [nombre=..] [zona=..] [estado=..] [documento=..]"},
    {"send_family_message", "send_family_message documento \"mensaje\""},
    {"list_family_messages", "list_family_messages documento"},
    {"deliver_message", "deliver_message MSG001"},
    {"report_pet", "report_pet lost|found especie nombre color tamano zona contacto [caracteristicas]"},
    {"list_pets", "list_pets [especie=..] [zona=..] [estado=..] [tipo=..]"},
    {"match_pets", "match_pets"},
    {"confirm_match", "confirm_match ID_PERDIDA ID_ENCONTRADA"},
    {"register_shelter", "register_shelter codigo nombre zona capacidad"},
    {"check_shelter", "check_shelter codigo"},
    {"list_shelters", "list_shelters"},
    {"link_shelter", "link_shelter codigo need|resource id"},
    {"register_entry", "register_entry codigo documento"},
    {"register_exit", "register_exit codigo documento"},
    {"shelter_report", "shelter_report"},
    {"summary", "summary"},
    {"activity", "activity [usuario]"}
  ]

  def uso(comando), do: Enum.find_value(@ayuda, "help", fn {c, u} -> c == comando && u end)
  def ayuda, do: "Comandos disponibles:\n" <> Enum.map_join(@ayuda, "\n", fn {_, u} -> "  " <> u end)

  def lista([], vacio, _fun), do: vacio
  def lista(items, _vacio, fun), do: Enum.map_join(items, "\n", fun)

  def zona(z) do
    s = Zona.estadisticas(z)
    "#{z.codigo} | #{z.nombre} | nivel #{z.nivel} (máx. #{s.nivel_maximo}) | #{s.afectados} afectados | #{s.sectores} sectores | #{s.puntos} puntos"
  end

  def arbol(nodo, sangria \\ 0) do
    linea = String.duplicate("  ", sangria) <> "- [#{nodo.tipo}] #{nodo.codigo} #{nodo.nombre} (#{nodo.nivel}, #{nodo.afectados} afectados)"
    Enum.join([linea | Enum.map(nodo.hijos, &arbol(&1, sangria + 1))], "\n")
  end

  def necesidad(n),
    do: "#{n.id} | #{n.tipo} | #{n.asignado}/#{n.cantidad} | prioridad #{n.prioridad} | #{n.estado} | zona #{n.zona} | #{n.descripcion} | por #{n.responsable}"

  def recurso(r),
    do: "#{r.codigo} | #{r.categoria} | #{r.cantidad} #{r.unidad} (máx. #{r.maximo}) | #{r.ubicacion} | zona #{r.zona}"

  def movimiento(m),
    do: "##{m.id} #{m.fecha} | #{m.tipo} | #{m.recurso} | #{m.cantidad} | #{m.usuario} | #{m.detalle}"

  def persona(p),
    do: "#{p.documento} | #{p.nombre} | edad #{p.edad || "?"} | zona #{p.zona} | #{p.estado} | cambios de estado: #{length(p.historial)}"

  def mensaje(m), do: "#{m.id} | #{m.fecha} | de #{m.remitente} para #{m.destinatario} | #{m.estado} | #{m.contenido}"

  def mascota(m),
    do: "#{m.id} | #{m.tipo} | #{m.especie} #{m.nombre} | #{m.color}, #{m.tamano} | zona #{m.zona} | #{m.estado} | contacto #{m.contacto}"

  def albergue(a),
    do: "#{a.codigo} | #{a.nombre} | zona #{a.zona} | ocupación #{Albergue.ocupacion(a)}/#{a.capacidad} (#{Albergue.porcentaje(a)}%) | cupos #{Albergue.cupos(a)}"

  def conteo(mapa) when map_size(mapa) == 0, do: "ninguno"
  def conteo(mapa), do: mapa |> Enum.sort() |> Enum.map_join(", ", fn {k, v} -> "#{clave(k)}: #{v}" end)

  defp clave({a, b}), do: "#{a}/#{b}"
  defp clave(k), do: to_string(k)

  def resumen(r) do
    """
    === RESUMEN GLOBAL ===
    Zonas: #{r.zonas} | Personas afectadas estimadas: #{r.afectados}
    Necesidades: #{conteo(r.necesidades)} (críticas pendientes: #{r.pendientes_criticas})
    Recursos restantes: #{conteo(r.stock)} | lotes críticos: #{r.recursos_criticos}
    Personas: #{conteo(r.personas)}
    Mensajes familiares: #{conteo(r.mensajes)}
    Mascotas: #{conteo(r.mascotas)}
    Albergues: #{r.albergues} | ocupación #{r.ocupacion}/#{r.capacidad}
    """
    |> String.trim_trailing()
  end
end
