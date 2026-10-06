require 'rails_helper'

# Una automatización por tiempo solo paraba si tenía `end_at_jabvox`, campo que ni siquiera
# estaba en el formulario: en la práctica no paraba nunca. Con intervalos en horas eso son
# decenas de envíos al día a un contacto real.
describe JabvoxTaskAutomation do
  let(:due) { Time.zone.local(2026, 11, 20, 18, 0) }

  def automation(attrs = {})
    described_class.new({ interval_unit_jabvox: 'hour', interval_count_jabvox: 2 }.merge(attrs))
  end

  describe 'modo before_due' do
    subject(:auto) do
      auto = automation(schedule_mode_jabvox: 'before_due', max_runs_jabvox: 3)
      allow(auto).to receive(:task).and_return(instance_double(JabvoxTask, due_at_jabvox: due))
      auto
    end

    # "3 avisos cada 2 horas antes" de una tarea que vence a las 18:00 → 12:00, 14:00, 16:00.
    it 'schedules the first notice N intervals before the due date' do
      expect(auto.send(:first_before_due_run)).to eq(Time.zone.local(2026, 11, 20, 12, 0))
    end

    it 'stops after the configured number of notices' do
      expect(auto.finished?(Time.zone.local(2026, 11, 20, 14, 0), 3)).to be true
      expect(auto.finished?(Time.zone.local(2026, 11, 20, 14, 0), 2)).to be false
    end

    it 'stops once the next run would land past the due date' do
      expect(auto.finished?(due + 1.hour, 1)).to be true
    end
  end

  describe 'modo recurring' do
    it 'stops at the max number of runs' do
      auto = automation(schedule_mode_jabvox: 'recurring', max_runs_jabvox: 5)
      expect(auto.finished?(1.hour.from_now, 5)).to be true
      expect(auto.finished?(1.hour.from_now, 4)).to be false
    end

    it 'stops at the end date' do
      auto = automation(schedule_mode_jabvox: 'recurring', end_at_jabvox: due)
      expect(auto.finished?(due + 1.minute, 1)).to be true
      expect(auto.finished?(due - 1.minute, 1)).to be false
    end

    # Sin tope sigue siendo indefinida: es legítimo para un recordatorio permanente, y lo
    # acota el hecho de que la automatización deja de correr cuando la tarea se completa.
    it 'runs indefinitely when neither limit is set' do
      expect(automation(schedule_mode_jabvox: 'recurring').finished?(1.year.from_now, 9_999)).to be false
    end
  end

  # Se invoca la validación directamente: un `valid?` completo haría que ActiveRecord
  # consultara la asociación real y el doble no sobrevive a eso.
  it 'requires a notice count and a task due date in before_due mode' do
    auto = automation(schedule_mode_jabvox: 'before_due')
    allow(auto).to receive(:task).and_return(instance_double(JabvoxTask, due_at_jabvox: nil))

    auto.send(:before_due_is_schedulable)

    expect(auto.errors[:max_runs_jabvox]).to be_present
    expect(auto.errors[:base].join).to include('fecha de vencimiento')
  end
end
