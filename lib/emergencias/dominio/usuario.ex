defmodule Emergencias.Dominio.Usuario do
  @moduledoc "Usuarios del sistema y credenciales."
  alias Emergencias.Util

  @tipos [:ciudadano, :voluntario, :coordinador, :administrador]
  def tipos, do: @tipos

  def crear(username, password, nombre, tipo, zona) do
    with :ok <- Util.no_vacio(username),
         :ok <- Util.no_vacio(password, :credenciales_invalidas),
         {:ok, tipo} <- Util.elegir(tipo, @tipos, :tipo_usuario_invalido) do
      {:ok,
       %{
         username: Util.codigo(username),
         nombre: if(Util.no_vacio(nombre) == :ok, do: String.trim(nombre), else: username),
         tipo: tipo,
         zona: Util.codigo(zona),
         hash: hash(password),
         creado_en: Util.ahora()
       }}
    end
  end

  def autenticar(usuario, password) do
    if usuario.hash == hash(password), do: :ok, else: {:error, :credenciales_invalidas}
  end

  defp hash(password), do: :crypto.hash(:sha256, "emergencias:" <> password) |> Base.encode16(case: :lower)

  def publico(usuario), do: Map.delete(usuario, :hash)
end

defmodule Emergencias.Dominio.Permisos do
  @moduledoc "Qué comandos puede ejecutar cada tipo de usuario (los roles superiores heredan los inferiores)."

  @ciudadano ~w(help disconnect list_needs register_need find_person report_person send_family_message
                list_family_messages report_pet list_pets check_shelter list_zones zone_status list_resources)
  @voluntario ~w(register_entry register_exit match_pets update_person deliver_message list_shelters
                 attend_need resource_in)
  @coordinador ~w(register_zone register_sector register_point register_resource resource_out
                  assign_resource transfer_resource register_shelter link_shelter confirm_match
                  close_need cancel_need summary critical_resources pending_needs shelter_report movements)
  @administrador ~w(activity)

  def todos, do: @ciudadano ++ @voluntario ++ @coordinador ++ @administrador
  def existe?(comando), do: comando in todos()

  def permitido?(:administrador, comando), do: existe?(comando)
  def permitido?(:coordinador, comando), do: comando in @ciudadano ++ @voluntario ++ @coordinador
  def permitido?(:voluntario, comando), do: comando in @ciudadano ++ @voluntario
  def permitido?(:ciudadano, comando), do: comando in @ciudadano
  def permitido?(_, _), do: false
end
