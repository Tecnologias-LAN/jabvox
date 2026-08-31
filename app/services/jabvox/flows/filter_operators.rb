# frozen_string_literal: true

# Operadores ofrecidos por tipo de dato en el editor de condiciones. Son los que
# `Engine::Condition` sabe evaluar: el editor no puede ofrecer una combinación
# que el motor luego no resuelva.
module Jabvox::Flows::FilterOperators
  OPERATORS_BY_TYPE = {
    'text' => [
      { 'value' => 'equals', 'label' => 'Es igual a' },
      { 'value' => 'not_equals', 'label' => 'Es diferente de' },
      { 'value' => 'contains', 'label' => 'Contiene' },
      { 'value' => 'not_contains', 'label' => 'No contiene' },
      { 'value' => 'starts_with', 'label' => 'Empieza por' },
      { 'value' => 'ends_with', 'label' => 'Termina por' },
      { 'value' => 'empty', 'label' => 'Está vacío' },
      { 'value' => 'not_empty', 'label' => 'No está vacío' }
    ],
    'number' => [
      { 'value' => 'eq', 'label' => 'Es igual a (=)' },
      { 'value' => 'gt', 'label' => 'Mayor que (>)' },
      { 'value' => 'gte', 'label' => 'Mayor o igual (>=)' },
      { 'value' => 'lt', 'label' => 'Menor que (<)' },
      { 'value' => 'lte', 'label' => 'Menor o igual (<=)' },
      { 'value' => 'empty', 'label' => 'Está vacío' },
      { 'value' => 'not_empty', 'label' => 'No está vacío' }
    ],
    'boolean' => [
      { 'value' => 'is_true', 'label' => 'Sí' },
      { 'value' => 'is_false', 'label' => 'No' }
    ],
    'list' => [
      { 'value' => 'in', 'label' => 'Es uno de' },
      { 'value' => 'not_in', 'label' => 'No es ninguno de' },
      { 'value' => 'empty', 'label' => 'Está vacío' },
      { 'value' => 'not_empty', 'label' => 'No está vacío' }
    ]
  }.freeze

  def self.for(data_type)
    OPERATORS_BY_TYPE[data_type.to_s] || OPERATORS_BY_TYPE['text']
  end
end
