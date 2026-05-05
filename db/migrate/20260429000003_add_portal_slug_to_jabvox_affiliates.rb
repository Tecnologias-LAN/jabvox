class AddPortalSlugToJabvoxAffiliates < ActiveRecord::Migration[7.1]
  def up
    add_column :jabvox_affiliates, :portal_slug, :string

    JabvoxAffiliate.find_each do |a|
      a.update_column(:portal_slug, generate_slug)
    end

    change_column_null :jabvox_affiliates, :portal_slug, false
    add_index :jabvox_affiliates, :portal_slug, unique: true
  end

  def down
    remove_column :jabvox_affiliates, :portal_slug
  end

  private

  def generate_slug
    loop do
      slug = SecureRandom.alphanumeric(8).downcase
      break slug unless JabvoxAffiliate.exists?(portal_slug: slug)
    end
  end
end
