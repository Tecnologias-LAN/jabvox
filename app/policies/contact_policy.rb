class ContactPolicy < ApplicationPolicy
  def index?
    true
  end

  def active?
    true
  end

  def import?
    @account_user.administrator?
  end

  # Descargar el CSV/Excel de ejemplo para importar: mismo privilegio que importar.
  def sample_import?
    @account_user.administrator?
  end

  # La vista previa de importación lee contactos existentes para detectar
  # duplicados: mismo nivel de privilegio que la importación en sí.
  def import_preview?
    @account_user.administrator?
  end

  def export?
    @account_user.administrator?
  end

  def search?
    true
  end

  def filter?
    true
  end

  def update?
    true
  end

  def contactable_inboxes?
    true
  end

  def destroy_custom_attributes?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def avatar?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end

ContactPolicy.prepend_mod_with('ContactPolicy')
