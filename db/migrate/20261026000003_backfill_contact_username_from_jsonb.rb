# Rellena contacts.username con el valor que ya vivía en
# additional_attributes.social_whatsapp_user_name (o social_profiles.whatsapp).
#
# Se hace con SQL directo, por cuenta y respetando el índice único parcial: si dentro
# de una misma cuenta dos contactos arrastran el mismo @usuario (dato histórico sucio),
# solo el de menor id se queda con la columna; el resto conserva su copia en el jsonb y
# no rompe la migración. Idempotente: solo toca filas con username aún nulo.
class BackfillContactUsernameFromJsonb < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute(<<~SQL.squish)
      WITH candidates AS (
        SELECT
          c.id,
          c.account_id,
          COALESCE(
            NULLIF(c.additional_attributes->>'social_whatsapp_user_name', ''),
            NULLIF(c.additional_attributes->'social_profiles'->>'whatsapp', '')
          ) AS uname
        FROM contacts c
        WHERE c.username IS NULL
      ),
      ranked AS (
        SELECT id, account_id, uname,
               ROW_NUMBER() OVER (PARTITION BY account_id, uname ORDER BY id) AS rn
        FROM candidates
        WHERE uname IS NOT NULL
      )
      UPDATE contacts
      SET username = ranked.uname
      FROM ranked
      WHERE contacts.id = ranked.id
        AND ranked.rn = 1;
    SQL
  end

  def down
    # No se revierte: el dato original sigue intacto en additional_attributes.
    # Vaciar la columna sería seguro pero innecesario; la bajamos en la migración de schema.
  end
end
