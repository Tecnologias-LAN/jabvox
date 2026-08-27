# frozen_string_literal: true

# Gestión de permisos granulares de Hermes por usuario dentro de la cuenta.
# Solo quien administra el Chat IA (jabvox_ai_chat_manage) puede ver/editar. El usuario
# NUNCA puede editar sus propios permisos vía el LLM: esto es una API de gestión aparte.
#
#   GET   .../jabvox/hermes_user_permissions        → lista (usuario → permisos)
#   PUT   .../jabvox/hermes_user_permissions/:user_id → fija los permisos de un usuario
class Api::V1::Accounts::Jabvox::HermesUserPermissionsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature 'jabvox_ai_chat'
  before_action -> { jabvox_authorize!('jabvox_ai_chat_manage') }

  def index
    members = Current.account.account_users.includes(:user)
    perms = JabvoxHermesUserPermission.where(account_id: Current.account.id).index_by(&:user_id)
    render json: members.map { |au|
      { user_id: au.user_id, name: au.user.name,
        permissions: perms[au.user_id]&.permissions_list || [] }
    }
  end

  def update
    target_user_id = params[:user_id].to_i
    # NIVEL 0: el usuario debe pertenecer a ESTA cuenta (evita fijar permisos cross-account).
    unless Current.account.account_users.exists?(user_id: target_user_id)
      return render json: { error: 'El usuario no pertenece a la cuenta' }, status: :not_found
    end

    permissions = sanitize_permissions(params[:permissions])
    record = JabvoxHermesUserPermission.find_or_initialize_by(
      account_id: Current.account.id, user_id: target_user_id
    )
    record.permissions_jabvox = permissions
    if record.save
      render json: { user_id: target_user_id, permissions: record.permissions_list }
    else
      render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  # Solo permisos del catálogo; descarta cualquier valor inventado (no se puede escalar).
  def sanitize_permissions(raw)
    Array(raw).map(&:to_s) & JabvoxHermesUserPermission::PERMISSIONS
  end
end
