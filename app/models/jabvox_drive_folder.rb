# frozen_string_literal: true

# Carpeta del Drive. La jerarquía es puramente lógica (metadatos): no existen
# carpetas físicas en MinIO, solo prefijos de objetos. `path` es la ruta
# materializada para navegación/búsqueda ("/Contactos/123/").
#
# == Schema Information
#
# Table name: jabvox_drive_folders
#
#  id            :bigint           not null, primary key
#  name          :string           not null
#  path          :string           default("/"), not null
#  system_folder :boolean          default(FALSE), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  contact_id    :bigint
#  created_by_id :bigint
#  parent_id     :bigint
#
# Indexes
#
#  idx_drive_folders_unique_name                            (account_id,parent_id,name) UNIQUE
#  index_jabvox_drive_folders_on_account_id                 (account_id)
#  index_jabvox_drive_folders_on_account_id_and_contact_id  (account_id,contact_id)
#  index_jabvox_drive_folders_on_account_id_and_path        (account_id,path)
#  index_jabvox_drive_folders_on_contact_id                 (contact_id)
#  index_jabvox_drive_folders_on_created_by_id              (created_by_id)
#  index_jabvox_drive_folders_on_parent_id                  (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (parent_id => jabvox_drive_folders.id)
#
class JabvoxDriveFolder < ApplicationRecord
  belongs_to :account
  belongs_to :parent, class_name: 'JabvoxDriveFolder', optional: true
  belongs_to :contact, optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :children, class_name: 'JabvoxDriveFolder', foreign_key: :parent_id,
                      inverse_of: :parent, dependent: :destroy
  has_many :files, class_name: 'JabvoxDriveFile', foreign_key: :folder_id,
                   inverse_of: :folder, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[account_id parent_id] }
  validate :no_slash_in_name
  validate :parent_in_same_account

  before_validation :compute_path

  ROOT_CONTACTS = 'contactos'

  # Carpeta raíz "contactos/" de la cuenta (creada bajo demanda, idempotente).
  def self.contacts_root(account)
    upsert_system_folder!(account, parent: nil, name: ROOT_CONTACTS,
                                   path: "/#{ROOT_CONTACTS}/")
  end

  # Carpeta de un contacto bajo "contactos/", con nombre legible y buscable
  # (<nombre>-<telefono>-<username>-<id>). Idempotente por path.
  def self.for_contact(account, contact)
    root = contacts_root(account)
    name = Jabvox::Drive::PathBuilder.contact_slug(contact)
    upsert_system_folder!(account, parent: root, name: name,
                                   path: "#{root.path}#{name}/".squeeze('/'),
                                   contact_id: contact.id)
  end

  # Carpeta de BANDEJA dentro del contacto: contactos/<contacto>/<bandeja>/.
  # Agrupa los adjuntos por la inbox donde el contacto escribió/recibió. Idempotente.
  def self.for_contact_inbox(account, contact, inbox)
    return for_contact(account, contact) if inbox.nil?

    parent = for_contact(account, contact)
    name = Jabvox::Drive::PathBuilder.inbox_slug(inbox)
    upsert_system_folder!(account, parent: parent, name: name,
                                   path: "#{parent.path}#{name}/".squeeze('/'),
                                   contact_id: contact.id)
  end

  # Busca-o-crea una carpeta de sistema por su PATH (clave única, a prueba de
  # concurrencia). Si dos requests simultáneos intentan crearla, el índice único
  # [account_id, path] hace fallar al segundo con RecordNotUnique; lo reintentamos
  # como búsqueda. Evita las carpetas duplicadas que producía el parent_id NULL.
  def self.upsert_system_folder!(account, parent:, name:, path:, contact_id: nil)
    existing = account.jabvox_drive_folders.find_by(path: path)
    return existing if existing

    account.jabvox_drive_folders.create!(
      parent_id: parent&.id, name: name, path: path,
      contact_id: contact_id, system_folder: true
    )
  rescue ActiveRecord::RecordNotUnique
    account.jabvox_drive_folders.find_by!(path: path)
  end

  private

  def compute_path
    base = parent&.path || '/'
    self.path = "#{base}#{name}/".squeeze('/')
  end

  def no_slash_in_name
    errors.add(:name, 'no puede contener "/"') if name.to_s.include?('/')
  end

  def parent_in_same_account
    return if parent.nil?

    errors.add(:parent, 'de otra cuenta') if parent.account_id != account_id
  end
end
