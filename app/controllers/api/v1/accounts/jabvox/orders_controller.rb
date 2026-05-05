module Api::V1::Accounts::Jabvox
  class OrdersController < Api::V1::Accounts::BaseController
    before_action :set_order, only: [:show, :update, :destroy, :send_to_alegra]

    def index
      orders = Current.account.jabvox_orders
      if params[:contact_id].present? && params[:conversation_id].present?
        orders = orders.where('contact_id = ? OR conversation_id = ?',
                              params[:contact_id], params[:conversation_id])
      elsif params[:contact_id].present?
        orders = orders.where(contact_id: params[:contact_id])
      elsif params[:conversation_id].present?
        orders = orders.where(conversation_id: params[:conversation_id])
      end
      orders = orders.includes(:jabvox_order_items).order(created_at: :desc)
      render json: orders.map { |o| order_json(o) }
    end

    def show
      render json: order_json(@order)
    end

    def create
      @order = Current.account.jabvox_orders.new(order_params)
      compute_totals(@order)
      @order.save!
      render json: order_json(@order), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def update
      @order.assign_attributes(order_params)
      compute_totals(@order)
      @order.save!
      render json: order_json(@order)
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def destroy
      @order.destroy!
      head :no_content
    end

    def send_to_alegra
      result = Jabvox::AlegraOrderSyncService.new(account: Current.account, order: @order).sync!
      render json: order_json(@order.reload)
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def set_order
      @order = Current.account.jabvox_orders.find(params[:id])
    end

    def order_params
      params.require(:order).permit(
        :contact_id, :conversation_id, :doc_type, :status, :notes,
        jabvox_order_items_attributes: [
          :id, :jabvox_product_id, :name_snapshot, :unit_price,
          :quantity, :discount_pct, :tax_pct, :_destroy
        ]
      )
    end

    def compute_totals(order)
      items = order.jabvox_order_items.reject(&:marked_for_destruction?)
      items.each do |i|
        base = i.unit_price.to_f * i.quantity.to_f
        i.line_total = base - (base * i.discount_pct.to_f / 100.0) + (base * i.tax_pct.to_f / 100.0)
      end
      subtotal      = items.sum { |i| i.unit_price.to_f * i.quantity.to_f }
      discount_total = items.sum { |i| i.unit_price.to_f * i.quantity.to_f * (i.discount_pct.to_f / 100.0) }
      tax_total     = items.sum { |i| i.unit_price.to_f * i.quantity.to_f * (i.tax_pct.to_f / 100.0) }
      order.subtotal       = subtotal
      order.discount_total = discount_total
      order.tax_total      = tax_total
      order.total          = subtotal - discount_total + tax_total
    end

    def order_json(order)
      {
        id: order.id,
        doc_type: order.doc_type,
        status: order.status,
        notes: order.notes,
        contact_id: order.contact_id,
        conversation_id: order.conversation_id,
        subtotal: order.subtotal,
        tax_total: order.tax_total,
        discount_total: order.discount_total,
        total: order.total,
        alegra_id: order.alegra_id,
        alegra_number: order.alegra_number,
        created_at: order.created_at,
        updated_at: order.updated_at,
        items: order.jabvox_order_items.map { |i|
          {
            id: i.id,
            jabvox_product_id: i.jabvox_product_id,
            name_snapshot: i.name_snapshot,
            unit_price: i.unit_price,
            quantity: i.quantity,
            discount_pct: i.discount_pct,
            tax_pct: i.tax_pct,
            line_total: i.line_total
          }
        }
      }
    end
  end
end
