class SuperAdmin::JabvoxDeletedLeadsController < SuperAdmin::ApplicationController
  # Administrate provides index/show. Adds a `restore` member action that recreates
  # the lead from its snapshot — only while still inside the retention window.
  def restore
    deleted_lead = JabvoxDeletedLead.find(params[:id])
    ok = Jabvox::LeadImport::TrashService.new(deleted_lead.account).restore(deleted_lead)
    redirect_to [:super_admin, deleted_lead],
                notice: ok ? 'Lead restaurado correctamente.' : 'No se pudo restaurar (fuera del plazo de 20 días o error).'
  end

  private

  # Scope Administrate to still-restorable entries by default; show all on demand.
  def scoped_resource
    params[:show_all].present? ? JabvoxDeletedLead : JabvoxDeletedLead.active
  end
end
