class ApiArraySerializer < ActiveModel::ArraySerializer
  def serializable_array
    JSONH.pack(super)
  end
end
