# OBSOLETA tras el upgrade a Chatwoot v4.16.2.
#
# Su propósito era desactivar defaults cuyo bit FlagShihTzu no cabía en el bigint
# `feature_flags` (bit >= 64), evitando un 500 al crear cuentas. El upgrade
# resuelve eso de raíz con el mecanismo multi-columna (feature_flags +
# feature_flags_ext_1, ver Featurable), y las constantes que esta migración usaba
# (Account::FEATURES, AccountFeatureFlagGuard::MAX_SAFE_FEATURE_BIT) ya no existen.
# Se deja como no-op para no romper `db:migrate` en entornos que aún no la
# tenían registrada; el saneamiento real de defaults renombrados lo hace la
# migración 20260629000000 (repurpose).
class SanitizeOverflowingFeatureDefaults < ActiveRecord::Migration[7.1]
  def up; end

  def down; end
end
