module JabvoxFieldMaskerHelper
  def jabvox_field_visible?(_field)
    true
  end

  def jabvox_mask(_field, value)
    value
  end

  def jabvox_mask_attrs(attrs)
    attrs
  end
end
