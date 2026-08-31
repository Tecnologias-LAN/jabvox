# frozen_string_literal: true

# Resultado uniforme de un handler. Nunca lanza: encapsula el error.
class Jabvox::Flows::Engine::NodeResult
  attr_reader :output, :error, :output_port, :wait

  def self.ok(output = nil, output_port: nil, wait: nil)
    new(ok: true, output: output, output_port: output_port, wait: wait)
  end

  def self.failure(error)
    new(ok: false, error: error)
  end

  def initialize(ok:, output: nil, error: nil, output_port: nil, wait: nil)
    @ok = ok
    @output = output
    @error = error
    @output_port = output_port
    @wait = wait
  end

  def ok?
    @ok
  end

  def wait?
    !@wait.nil?
  end
end
