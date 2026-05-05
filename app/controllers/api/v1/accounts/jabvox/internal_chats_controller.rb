# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::InternalChatsController < Api::V1::Accounts::BaseController
  before_action :check_enabled
  before_action :set_chat, only: %i[messages send_message mark_read]

  def index
    chats = JabvoxInternalChat
            .for_user(current_user.id)
            .where(account: Current.account)
            .includes(:members, :users)
            .ordered
    render json: chats.map { |c| serialize_chat(c) }
  end

  def create
    chat = params[:chat_type] == 'group_chat' ? create_group : find_or_create_direct
    render json: serialize_chat(chat)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def messages
    msgs = @chat.messages.includes(:sender).order(created_at: :asc).last(100)
    render json: msgs.map { |m| serialize_message(m) }
  end

  def send_message
    content = params[:content].to_s.strip
    return render json: { error: 'content required' }, status: :unprocessable_entity if content.blank?

    msg = @chat.messages.create!(sender: current_user, content: content)
    render json: serialize_message(msg)
  end

  def mark_read
    @chat.members.find_by(user_id: current_user.id)&.update!(unread_count: 0, last_read_at: Time.current)
    render json: { ok: true }
  end

  def unread_count
    total = JabvoxInternalChatMember
            .joins(:chat)
            .where(user_id: current_user.id, jabvox_internal_chats: { account_id: Current.account.id })
            .sum(:unread_count)
    render json: { count: total }
  end

  def account_users
    users = Current.account.users.order(:name).map do |u|
      { id: u.id, name: u.name, avatar_url: u.avatar_url }
    end
    render json: users
  end

  private

  def check_enabled
    render json: { error: 'Internal chat not enabled' }, status: :forbidden unless Current.account.jabvox_internal_chat_enabled_jabvox?
  end

  def set_chat
    @chat = JabvoxInternalChat.for_user(current_user.id).where(account: Current.account).find(params[:id])
  end

  def create_group
    chat = JabvoxInternalChat.create!(
      account: Current.account,
      created_by: current_user,
      chat_type: :group_chat,
      name: params[:name].to_s.strip
    )
    member_ids = (Array(params[:member_ids]).map(&:to_i) + [current_user.id]).uniq
    member_ids.each do |uid|
      chat.members.create!(user_id: uid) if Current.account.users.exists?(uid)
    end
    chat
  end

  def find_or_create_direct
    other_id = params[:user_id].to_i
    mine = JabvoxInternalChatMember.where(user_id: current_user.id).select(:chat_id)
    existing = JabvoxInternalChat
               .where(account: Current.account, chat_type: :direct, id: mine)
               .joins(:members)
               .where(jabvox_internal_chat_members: { user_id: other_id })
               .first
    return existing if existing

    chat = JabvoxInternalChat.create!(account: Current.account, created_by: current_user, chat_type: :direct)
    chat.members.create!(user_id: current_user.id)
    chat.members.create!(user_id: other_id) if Current.account.users.exists?(other_id)
    chat
  end

  def serialize_chat(chat)
    member = chat.members.find { |m| m.user_id == current_user.id }
    other_user = other_chat_user(chat)

    {
      id: chat.id,
      chat_type: chat.chat_type,
      name: chat_display_name(chat, other_user),
      avatar_url: chat.direct? ? other_user&.avatar_url : nil,
      unread_count: member&.unread_count || 0,
      last_message: serialize_last_message(chat.messages.order(created_at: :desc).first),
      members: serialize_users(chat.users)
    }
  end

  def other_chat_user(chat)
    return nil unless chat.direct?

    chat.users.find { |u| u.id != current_user.id }
  end

  def chat_display_name(chat, other_user)
    chat.group_chat? ? chat.name : other_user&.name
  end

  def serialize_users(users)
    users.map { |u| { id: u.id, name: u.name, avatar_url: u.avatar_url } }
  end

  def serialize_last_message(msg)
    return nil unless msg

    { content: msg.content, created_at: msg.created_at, sender_id: msg.sender_id }
  end

  def serialize_message(msg)
    {
      id: msg.id,
      content: msg.content,
      created_at: msg.created_at,
      sender: { id: msg.sender_id, name: msg.sender.name, avatar_url: msg.sender.avatar_url }
    }
  end
end
