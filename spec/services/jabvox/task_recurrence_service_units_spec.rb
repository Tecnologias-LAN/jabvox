require 'rails_helper'

# La recurrencia solo admitía día/semana/mes/año: no había forma de repetir una tarea
# dentro del mismo día sin crear una por cada repetición.
describe Jabvox::TaskRecurrenceService do
  let(:base) { Time.zone.local(2026, 11, 20, 9, 0) }

  def next_due(unit, count)
    service = described_class.allocate
    task = instance_double(JabvoxTask, recurrence_count_jabvox: count,
                                       recurrence_unit_jabvox: unit, due_at_jabvox: base)
    service.instance_variable_set(:@task, task)
    base + service.send(:interval)
  end

  it 'offers intraday units alongside the existing ones' do
    expect(described_class::UNITS).to eq(%w[minute hour day week month year])
  end

  it 'advances by minutes' do
    expect(next_due('minute', 30)).to eq(Time.zone.local(2026, 11, 20, 9, 30))
  end

  it 'advances by hours' do
    expect(next_due('hour', 2)).to eq(Time.zone.local(2026, 11, 20, 11, 0))
  end

  it 'keeps the previous units working' do
    expect(next_due('day', 2)).to eq(Time.zone.local(2026, 11, 22, 9, 0))
    expect(next_due('week', 2)).to eq(Time.zone.local(2026, 12, 4, 9, 0))
  end
end
