# frozen_string_literal: true

# Resultado completo de validar un grafo. Se recogen TODOS los problemas y se
# devuelven juntos: nunca "el primer error".
class Jabvox::Flows::Validation::Result
  attr_reader :issues, :mode

  def initialize(issues, mode)
    @issues = issues
    @mode = mode
  end

  def errors
    @errors ||= @issues.select(&:error?)
  end

  def warnings
    @warnings ||= @issues.select(&:warning?)
  end

  # Válido = sin ningún issue de severidad error. Los avisos NUNCA bloquean.
  def valid?
    errors.empty?
  end

  def error_count
    errors.length
  end

  def warning_count
    warnings.length
  end

  # Issues que BLOQUEAN el guardado en el modo dado: en permisivo solo los
  # estructurales, en estricto todos los errores.
  def blocking
    return errors if @mode == :strict

    errors.select { |issue| Jabvox::Flows::Validation::Codes::STRUCTURAL.include?(issue.code) }
  end

  def blocking?
    blocking.any?
  end

  def to_h
    { 'valid' => valid?, 'errorCount' => error_count, 'warningCount' => warning_count,
      'issues' => @issues.map(&:to_h) }
  end
end
