class TeamSerializer < ActiveModel::Serializer
  attributes :name, :logo_url, :pt, :stats_id, :disable_pt, :remove_pt

  def stats_id
    object.stats_id
  end

  def disable_pt
    Prediction.prediction_made?(stats_id, options[:type], '', options[:user])
  end

  def pt
    object.pt(options)
  end

  def remove_pt
    object.pt(options) <= 15
  end
end
