class Competition < ActiveRecord::Base
  has_many :members, source: :memberable
  attr_protected

  def process_predictions
    raise 'Competition already processed!' if self.state == 'processed'

    competition_name = self.formatted_name
    predictions = if ['win_the_cup', 'mvp'].include?(competition_name)
                    Prediction.where(prediction_type: competition_name)
                  elsif group_type?
                    group = Group.where(name: self.name).first
                    team_ids = group.teams.pluck(:stats_id).map(&:to_s)
                    Prediction.where(prediction_type: 'win_groups', stats_id: team_ids)
                  end

    predictions.each { |p| p.process! }
    group.update_attribute(:closed, true) if group
    self.update_attribute(:state, 'processed')
  end

  def formatted_name
    self.name.downcase.gsub(' ', '_')
  end

  def group_type?
    !!(self.formatted_name =~ /^group/)
  end
end
