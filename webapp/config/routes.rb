Fantasysports::Application.routes.draw do
  match "*path" => redirect("https://fairmarketfantasy.com/%{path}"), :constraints => { :subdomain => "www" }, :via => [:get] if Rails.env == 'production'

  root 'pages#index'

  devise_for :users, :controllers => { :omniauth_callbacks => "users/omniauth_callbacks",
                                       :sessions => 'users/sessions',
                                       :registrations => "users/registrations",
                                       :confirmations => "users/confirmations" }
  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".
  Rails.application.routes.draw do
    devise_for :admin_users, ActiveAdmin::Devise.config
    ActiveAdmin.routes(self)
    # oauth routes can be mounted to any path (ex: /oauth2 or /oauth)
    mount Devise::Oauth2Providable::Engine => '/oauth2'
  end
  devise_scope :user do
    get "users", :to => "users#index", :as => "users_index"
    post "users/uploads", :to => "users/registrations#update"
  end

  # You can have the root of your site routed with "root"
  get '/terms' => 'pages#terms'
  get '/guide' => 'pages#guide'
  get '/landing' => 'pages#landing'
  get '/about' => 'pages#about'
  get '/sign_up' => 'pages#sign_up'

  get 'join_contest/:invitation_code', to: "contests#join", as: 'join_contest'

  #for /users/:id
  resources :users, only: [:show] do
    collection do
      get 'name_taken',      action: :name_taken
      get 'token_plans',      action: :token_plans
      post 'set_username',      action: :set_username
      post 'add_money',      action: :add_money
      post 'add_tokens',      action: :add_tokens
      post 'withdraw_money', action: :withdraw_money
    end
  end

  resources :recipients, only: [:index, :create] do
    collection do
      delete '', action: :destroy
    end
  end

  resources :cards, only: [:index, :create, :destroy]

  resources :rosters, only: [:create, :show, :destroy] do
    collection do
      get 'mine', :action => 'mine'
      get 'past_stats', :action => 'past_stats'
      get 'in_contest/:contest_id', :action => 'in_contest'
    end
    member do post 'submit', :action => 'submit'
      post 'add_player/:player_id', :action => 'add_player'
      post 'remove_player/:player_id', :action => 'remove_player'
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
