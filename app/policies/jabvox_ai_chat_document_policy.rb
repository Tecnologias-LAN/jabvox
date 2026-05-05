class JabvoxAiChatDocumentPolicy < ApplicationPolicy
  def index?   = true
  def update?  = administrator?
  def destroy? = administrator?
end