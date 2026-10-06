require 'rails_helper'

# Al abrir el tablero nadie ha elegido filtro todavía. Si un marcador `{{CICLO}}` se queda
# sin valor, la consulta sale con el texto literal y la base la rechaza: el tablero abre
# con todos los widgets en 422. De ahí los valores por defecto del propio widget.
describe Api::V1::Accounts::Jabvox::Analytics::DashboardWidgetsController do
  let(:controller_instance) { described_class.new }
  let(:widget) { instance_double(JabvoxAnalyticsDashboardWidget, config_jabvox: config) }
  let(:config) { { 'param_defaults' => { 'CICLO' => '202613' } } }

  def resolve(global_filters = nil)
    payload = global_filters.nil? ? {} : { global_filters: global_filters }
    controller_instance.params = ActionController::Parameters.new(payload)
    controller_instance.instance_variable_set(:@widget, widget)
    controller_instance.send(:sql_placeholder_values)
  end

  it 'usa el valor por defecto cuando no llega ningún filtro' do
    expect(resolve).to eq('CICLO' => '202613')
  end

  it 'el filtro elegido gana sobre el valor por defecto' do
    expect(resolve({ params: { 'CICLO' => '202615' } })).to eq('CICLO' => '202615')
  end

  it 'vuelve al valor por defecto si el usuario deja el filtro vacío' do
    expect(resolve({ params: { 'CICLO' => '' } })).to eq('CICLO' => '202613')
  end

  it 'conserva el valor por defecto de los marcadores que el filtro no toca' do
    allow(widget).to receive(:config_jabvox).and_return(
      'param_defaults' => { 'CICLO' => '202613', 'ZONA' => '1805' }
    )
    expect(resolve({ params: { 'CICLO' => '202615' } })).to eq('CICLO' => '202615', 'ZONA' => '1805')
  end

  context 'when the widget declares no defaults' do
    let(:config) { {} }

    it 'no inventa valores' do
      expect(resolve).to eq({})
    end
  end
end
