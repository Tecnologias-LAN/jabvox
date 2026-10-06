require 'rails_helper'

describe Jabvox::AutomationTemplateParamsService do
  let(:contact) do
    instance_double(Contact, name: 'Ana Pérez', email: 'ana@x.co', phone_number: '+573001112233',
                             identifier: 'C-1', custom_attributes: { 'ciudad' => 'Medellín' })
  end
  let(:task) do
    instance_double(JabvoxTask, title_jabvox: 'Llamar a Ana',
                                due_at_jabvox: Time.zone.local(2026, 11, 20, 9, 0))
  end
  let(:stage) { instance_double(JabvoxKanbanStage, name_jabvox: 'En gestión') }

  def resolve(mapping, **args)
    described_class.new(mapping: mapping, **args).call
  end

  it 'resolves contact, task, custom attribute and fixed values' do
    mapping = {
      '1' => { 'source' => 'contact', 'field' => 'name' },
      '2' => { 'source' => 'task', 'field' => 'title_jabvox' },
      '3' => { 'source' => 'task', 'field' => 'due_date' },
      '4' => { 'source' => 'custom', 'field' => 'ciudad' },
      '5' => { 'source' => 'fixed', 'value' => 'Noviembre' },
      '6' => { 'source' => 'task', 'field' => 'stage_name' }
    }

    expect(resolve(mapping, contact: contact, task: task, stage: stage)).to eq(
      '1' => 'Ana Pérez', '2' => 'Llamar a Ana', '3' => '20/11/2026',
      '4' => 'Medellín', '5' => 'Noviembre', '6' => 'En gestión'
    )
  end

  # El mapeo llega del formulario, así que un `field` arbitrario no puede convertirse en
  # una llamada a cualquier método del modelo: eso filtraría tokens o ejecutaría acciones.
  describe 'field whitelist' do
    it 'returns empty for contact fields outside the whitelist' do
      %w[auth_token access_token custom_attributes send destroy].each do |field|
        result = resolve({ '1' => { 'source' => 'contact', 'field' => field } }, contact: contact)
        expect(result).to eq('1' => ''), "filtró contact.#{field}"
      end
    end

    it 'returns empty for task fields outside the whitelist' do
      result = resolve({ '1' => { 'source' => 'task', 'field' => 'destroy' } }, task: task)
      expect(result).to eq('1' => '')
    end

    it 'ignores non-numeric variable positions' do
      expect(resolve({ 'x' => { 'source' => 'contact', 'field' => 'name' } }, contact: contact)).to eq({})
    end
  end

  it 'yields blanks instead of raising when the record is missing' do
    mapping = { '1' => { 'source' => 'contact', 'field' => 'name' }, '2' => { 'source' => 'fixed', 'value' => 'X' } }
    expect(resolve(mapping)).to eq('1' => '', '2' => 'X')
  end

  it 'tolerates a mapping that is not a hash' do
    expect(resolve(nil, contact: contact)).to eq({})
  end
end
