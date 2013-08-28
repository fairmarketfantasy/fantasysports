class RecipientSerializer < ActiveModel::Serializer
  attributes :id, :legal_name, :routing, :account_num
end
