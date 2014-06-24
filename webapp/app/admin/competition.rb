ActiveAdmin.register Competition do
  actions :all, except: [:destroy, :edit]

  index do
    column :id
    column :name
    column :state
    actions defaults: true do |competition|
      link_to 'Process', process_predictions_admin_competition_path(competition), method: :put
    end
  end

  member_action :process_predictions, method: :put do
    Competition.find(params[:id]).process_predictions
    redirect_to({action: :index}, { notice: 'Competition is processed.'})
  end
end
