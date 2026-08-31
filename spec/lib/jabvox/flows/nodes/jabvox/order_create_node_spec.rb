# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Jabvox::OrderCreateNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let(:contact) { create(:contact, account: account, name: 'Ana') }
  let(:items) { [{ 'name_snapshot' => 'Plan Oro', 'quantity' => 2, 'unit_price' => 100 }] }

  describe described_class do
    it 'crea la orden con sus líneas y recalcula los totales' do
      result = run_node(described_class, ctx,
                        { 'contactId' => contact.id, 'doc_type' => 'SALE', 'items' => items })

      expect(result).to be_ok
      order = account.jabvox_orders.last
      expect(order.doc_type).to eq('SALE')
      expect(order.contact_id).to eq(contact.id)
      expect(order.subtotal.to_f).to eq(200.0)
      expect(order.total.to_f).to eq(200.0)
      expect(result.output['items'].first).to include('name_snapshot' => 'Plan Oro', 'line_total' => 200.0)
    end

    it 'aplica descuento e impuesto igual que el panel' do
      run_node(described_class, ctx,
               { 'items' => [{ 'name_snapshot' => 'X', 'quantity' => 1, 'unit_price' => 100,
                               'discount_pct' => 10, 'tax_pct' => 19 }] })

      order = account.jabvox_orders.last
      expect(order.subtotal.to_f).to eq(100.0)
      expect(order.discount_total.to_f).to eq(10.0)
      expect(order.tax_total.to_f).to eq(19.0)
      expect(order.total.to_f).to eq(109.0)
    end

    it 'crea como COTIZACIÓN (QUOTE) por defecto' do
      run_node(described_class, ctx, { 'items' => items })

      expect(account.jabvox_orders.last.doc_type).to eq('QUOTE')
    end

    it 'acepta las líneas como texto JSON' do
      run_node(described_class, ctx, { 'items' => items.to_json })

      expect(account.jabvox_orders.last.jabvox_order_items.first.name_snapshot).to eq('Plan Oro')
    end

    it 'rechaza un tipo de documento fuera de la lista' do
      expect(run_node(described_class, ctx, { 'doc_type' => 'FACTURA', 'items' => items }).error)
        .to match(/Tipo de documento no válido/)
    end

    it 'NO crea la orden con el contacto de otro tenant' do
      ajeno = create(:contact, account: create(:account))

      expect(run_node(described_class, ctx, { 'contactId' => ajeno.id, 'items' => items }).error)
        .to match(/no existe en esta cuenta/)
      expect(account.jabvox_orders.count).to eq(0)
    end

    it 'no acepta una conversación de otra cuenta' do
      otra = create(:account)
      ajena = create(:conversation, account: otra)

      expect(run_node(described_class, ctx, { 'conversationId' => ajena.id, 'items' => items }).error)
        .to match(/no existe en esta cuenta/)
    end

    it 'dice el NÚMERO de la línea sin producto ni descripción' do
      malas = [{ 'name_snapshot' => 'Bien', 'quantity' => 1 }, { 'quantity' => 1, 'unit_price' => 5 }]

      expect(run_node(described_class, ctx, { 'items' => malas }).error)
        .to match(/La línea 2 no tiene producto ni descripción/)
    end

    it 'rechaza una cantidad que no es mayor que 0 diciendo la línea' do
      expect(run_node(described_class, ctx,
                      { 'items' => [{ 'name_snapshot' => 'X', 'quantity' => 0 }] }).error)
        .to match(/La cantidad de la línea 1 \("X"\) debe ser mayor que 0/)
    end

    it 'rechaza un precio negativo diciendo la línea' do
      expect(run_node(described_class, ctx,
                      { 'items' => [{ 'name_snapshot' => 'X', 'unit_price' => -5 }] }).error)
        .to match(/El precio de la línea 1 \("X"\) no puede ser negativo/)
    end

    it 'rechaza un porcentaje fuera de 0..100 diciendo la línea' do
      expect(run_node(described_class, ctx,
                      { 'items' => [{ 'name_snapshot' => 'X', 'tax_pct' => 150 }] }).error)
        .to match(/El impuesto de la línea 1 \("X"\) debe estar entre 0 y 100/)
    end

    it 'rechaza unas líneas que no son JSON válido' do
      expect(run_node(described_class, ctx, { 'items' => 'esto no es json' }).error)
        .to match(/no son un JSON válido/)
    end

    it 'crea una orden sin líneas cuando el editor viene vacío' do
      result = run_node(described_class, ctx, { 'contactId' => contact.id, 'items' => [] })

      expect(result).to be_ok
      expect(result.output['items']).to eq([])
      expect(result.output['total']).to eq(0.0)
    end
  end

  describe Jabvox::Flows::Nodes::Jabvox::OrderUpdateNode do
    let(:order) do
      account.jabvox_orders.create!(contact: contact, doc_type: 'QUOTE', status: 'draft',
                                    notes: 'nota original')
    end

    it 'actualiza SOLO lo configurado y no borra lo demás' do
      result = run_node(described_class, ctx, { 'orderId' => order.id, 'status' => 'approved' })

      expect(result).to be_ok
      expect(order.reload.status).to eq('approved')
      expect(order.notes).to eq('nota original')
    end

    it 'SUMA las líneas nuevas a las existentes y recalcula los totales' do
      order.jabvox_order_items.create!(name_snapshot: 'Vieja', quantity: 1, unit_price: 50)

      run_node(described_class, ctx,
               { 'orderId' => order.id, 'items' => [{ 'name_snapshot' => 'Nueva', 'quantity' => 1,
                                                      'unit_price' => 30 }] })

      expect(order.reload.jabvox_order_items.pluck(:name_snapshot)).to contain_exactly('Vieja', 'Nueva')
      expect(order.total.to_f).to eq(80.0)
    end

    it 'elimina una línea existente marcada para borrar' do
      vieja = order.jabvox_order_items.create!(name_snapshot: 'Vieja', quantity: 1, unit_price: 50)

      run_node(described_class, ctx,
               { 'orderId' => order.id, 'items' => [{ 'id' => vieja.id, '_destroy' => true }] })

      expect(order.reload.jabvox_order_items.count).to eq(0)
      expect(order.total.to_f).to eq(0.0)
    end

    it 'falla si se marca para borrar una línea sin ID' do
      expect(run_node(described_class, ctx,
                      { 'orderId' => order.id, 'items' => [{ '_destroy' => true }] }).error)
        .to match(/La línea 1 está marcada para eliminar pero no tiene ID de línea/)
    end

    it 'falla si no se configuró nada que actualizar' do
      expect(run_node(described_class, ctx, { 'orderId' => order.id }).error)
        .to match(/nada que actualizar/)
    end

    it 'no encuentra una orden de otra cuenta' do
      otra = create(:account)
      ajena = otra.jabvox_orders.create!(doc_type: 'QUOTE', status: 'draft')

      expect(run_node(described_class, ctx, { 'orderId' => ajena.id, 'status' => 'x' }).error)
        .to match(/no existe en esta cuenta/)
    end

    it 'falla si el ID de la orden llega vacío' do
      expect(run_node(described_class, ctx, { 'orderId' => '', 'status' => 'x' }).error)
        .to match(/Falta el ID de la orden/)
    end
  end
end
