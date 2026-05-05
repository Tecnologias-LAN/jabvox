class JabvoxAiChatMessagePolicy < ApplicationPolicy
  def index?  = true
  def create? = true
  def destroy? = true
  def my_access? = true
  def sessions? = true
end
