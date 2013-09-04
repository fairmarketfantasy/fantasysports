class RecipientSerializer < ActiveModel::Serializer
  attributes :id, :legal_name, :last4, :bank_name
end
