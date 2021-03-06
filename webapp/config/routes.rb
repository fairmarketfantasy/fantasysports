Fantasysports::Application.routes.draw do
  post "team_predictions/create"
  match "*path" => redirect("https://predictthat.com/%{path}"), :constraints => { :subdomain => "www" }, :via => [:get] if Rails.env == 'production'

  root 'pages#index'

  devise_for :users, :controllers => { :omniauth_callbacks => "users/omniauth_callbacks",
                                       :sessions => 'users/sessions',
                                       :passwords => 'users/passwords',
                                       :registrations => "users/registrations",
                                       :confirmations => "users/confirmations" }
  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".
  Rails.application.routes.draw do
  post "team_predictions/create"
    devise_for :admin_users, ActiveAdmin::Devise.config
    ActiveAdmin.routes(self)
    # oauth routes can be mounted to any path (ex: /oauth2 or /oauth)
    mount Devise::Oauth2Providable::Engine => '/oauth2'
  end
  devise_scope :user do
    get "users", :to => "users#index", :as => "users_index"
    post "users/uploads", :to => "users/registrations#update"
  end

  constraint = lambda { |request| request.env["warden"].authenticate? and request.env['warden'].user.admin? }

  mount Sidekiq::Monitor::Engine => '/sidekiq', :constraints => constraint

  # You can have the root of your site routed with "root"
  get '/healthcheck' => 'application#healthcheck'
  post '/support' => 'pages#support'
  get '/public' => 'pages#public'
  get '/support' => 'pages#supports'
  get '/conditions' => 'pages#conditions'
  get '/guide' => 'pages#guide'
  get '/landing' => 'pages#landing'
  get '/about' => 'pages#about'
  get '/sign_up' => 'pages#sign_up'
  get '/leaderboard' => 'leaderboard#index'
  get '/prestige_chart' => 'leaderboard#prestige'
  get '/categories' => 'categories#index'
  get '/pages/mobile/forgot_password' => 'mobile_pages#forgot_password'
  get '/pages/mobile/conditions' => 'mobile_pages#conditions'
  get '/pages/mobile/terms' => 'mobile_pages#terms'
  get '/pages/mobile/rules' => 'mobile_pages#rules'
  get '/home' => 'sports#home'
  post '/create_prediction' => 'sports#create_prediction'
  delete '/trade_prediction', to: 'sports#trade_prediction'

  get 'join_contest/:invitation_code', to: "contests#join", as: 'join_contest'

  #for /users/:id
  resources :users, only: [:index, :show] do
    collection do
      post 'agree_to_terms',     action: :agree_to_terms
      get 'unsubscribe',     action: :unsubscribe
      get 'name_taken',      action: :name_taken
      get 'token_plans',     action: :token_plans
      post 'set_username',   action: :set_username
      post 'add_money',      action: :add_money
      get  'paypal_return/:type',  action: :paypal_return
      get  'paypal_waiting',  action: :paypal_waiting
      get  'paypal_cancel',  action: :paypal_cancel
      post  'reset_password', action: :reset_password
      post 'add_tokens',     action: :add_tokens
      post 'withdraw_money', action: :withdraw_money
      post 'activate_trial', action: :activate_trial
      delete 'deactivate_account', action: :deactivate_account
    end
  end

  resources :recipients, only: [:index, :create] do
    collection do
      delete '', action: :destroy
    end
  end

  resources :cards, only: [:index, :create, :destroy] do
    collection do
      get 'add_url', :action => 'add_url'
      get 'token_redirect_url', :action => 'token_redirect_url'
      get 'charge_url', :action => 'charge_url'
      get 'charge_redirect_url', :action => 'charge_redirect_url'
    end
  end

  resources :rosters, only: [:new, :create, :show, :destroy] do
    collection do
      post 'enter_league/:league_id', :action => 'create_league_entry'
      get 'mine', :action => 'mine'
      get 'past_stats', :action => 'past_stats'
      get 'in_contest/:contest_id', :action => 'in_contest'
      get 'public/:view_code', :action => 'public_roster'
      get 'sample', :action => 'sample_roster'
    end
    member do
      post 'submit', :action => 'submit'
      post 'toggle_remove_bench', :action => 'toggle_remove_bench'
      post 'autofill', :action => 'autofill'
      post 'add_player/:player_id/*position', :action => 'add_player' # allow '/' in position by using '*'
      post 'remove_player/:player_id', :action => 'remove_player'
      post 'share', :action => 'share'
    end
  end

  get "/transactions" => 'transaction_record#index'

  resources :promo, only: [:create] do
    collection do
      post 'redeem', :action => 'redeem'
    end
  end

  resources :contests, only: [:create] do
    collection do
      get 'for_market/:id', :action => 'for_market'
      post 'join'
      get 'join'
    end

    member do
      post 'invite'
    end
  end

  #for /games/:game_stats_id
  resources :games, only: [:show] do
    collection do
      get 'for_market/:id', :action => 'for_market'
    end
  end

  resources :players, only: [:index] do
    collection do
      get 'mine', :action => 'mine'
      get 'public', :action => 'public'
      get 'for_roster/:id', :action => 'for_roster'
    end
  end

  resources :markets, only: [:index, :show] do
  end

  resources :events, only: [] do
    collection do
      get 'for_players', :action => 'for_players'
    end
  end

  resources :push_devices, :only => [:create]

  resources :individual_predictions, :only => [:create, :show, :update] do
    collection do
      get 'mine', :action => 'mine'
    end
  end

  resources :game_rosters, :only => [:create, :show, :update] do
    collection do
      post 'autofill', action: 'autofill'
      post 'new_autofill', action: 'new_autofill'
      get 'in_contest/:contest_id', action: 'in_contest'
    end
  end

  resources :game_predictions, :only => [:show, :create] do
    collection do
      get 'mine', action: 'mine'
      get 'day_games', action: 'day_games'
      get 'new_day_games', action: 'new_day_games'
      get 'sample', action: 'sample'
    end
  end
  #Stripe webhooks
  post '/webhooks', to: "webhooks#new"


  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end
