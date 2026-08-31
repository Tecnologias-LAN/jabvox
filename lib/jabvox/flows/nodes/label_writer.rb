# frozen_string_literal: true

# Escritura de ETIQUETAS con leer-unir-escribir seguro ante concurrencia.
#
# `acts_as_taggable_on` FIJA el set completo (`label_list=`), así que dos
# ejecuciones simultáneas sobre la misma conversación se pisan: la segunda parte
# de un set leído antes de que la primera guardase y borra su etiqueta. En
# TypeScript esto se resolvía con un lock en Redis y reintentos; dentro de Rails
# hay algo MÁS fuerte y sin dependencias: `lock!` toma un bloqueo de fila real en
# PostgreSQL, así que el leer-unir-escribir es atómico de verdad.
module Jabvox::Flows::Nodes::LabelWriter
  module_function

  # Aplica `labels` sobre el registro (:add o :remove) y devuelve el set final.
  def apply(record, labels, mode)
    record.transaction do
      # `lock!` rechaza un registro con cambios en memoria, y el que llega de un
      # paso anterior puede traerlos. Se descartan: la fuente de verdad de las
      # etiquetas es la fila, no lo que quedara suelto en el objeto.
      record.reload if record.changed?
      # SELECT ... FOR UPDATE: nadie más lee esta fila hasta el commit, así que
      # el leer-unir-escribir es atómico de verdad.
      record.lock!
      current = record.label_list.to_a.map(&:to_s)
      record.update!(label_list: combine(current, labels, mode))
    end
    record.reload.label_list.to_a.map(&:to_s)
  end

  def combine(current, labels, mode)
    mode == :remove ? current - labels : (current + labels).uniq
  end

  # Corta el paso si alguna etiqueta NO existe en el catálogo de la cuenta.
  #
  # `label_list=` CREA el tag al vuelo, así que un nombre mal escrito queda
  # aplicado pero NO existe como `Label` de la cuenta (son tablas distintas): no
  # sale en el catálogo ni en los desplegables, y ni el renombrado ni el borrado
  # de etiquetas la alcanzan.
  def assert_exist!(account, labels, mode)
    titles = account.labels.pluck(:title)
    unknown = labels.reject { |l| titles.include?(l) }
    return if unknown.empty?

    raise Jabvox::Flows::Engine::ExecutionError, missing_message(unknown, titles, mode)
  end

  def missing_message(unknown, titles, mode)
    verb = mode == :remove ? 'quitar' : 'añadir'
    noun = unknown.length == 1 ? 'la etiqueta' : 'las etiquetas'
    exists = unknown.length == 1 ? 'existe' : 'existen'
    "No se puede #{verb} #{noun} #{unknown.map { |l| "«#{l}»" }.join(', ')}: no #{exists} en esta " \
      'cuenta de Jabvox. Créala en Ajustes → Etiquetas (o corrige el nombre en el paso: puede ser un ' \
      "error de escritura si importaste el flujo). Etiquetas disponibles: #{available(titles)}."
  end

  def available(titles)
    titles.any? ? titles.sort.join(', ') : '(la cuenta no tiene ninguna)'
  end

  # `Label` fuerza el título a MINÚSCULAS al guardarlo, así que comparar contra
  # el catálogo con la grafía del usuario daría un falso "no existe".
  def normalize(labels)
    Jabvox::Flows::Nodes::Params.str_list(labels).map(&:downcase).uniq
  end
end
