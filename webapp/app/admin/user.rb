ActiveAdmin.register User do
  filter :email
  filter :username
  filter :inviter_id

  index do
=begin
------------------------+-----------------------------+----------------------------------------------------
 id                     | integer                     | not null default nextval('users_id_seq'::regclass)
 name                   | character varying(255)      | not null
 created_at             | timestamp without time zone |
 updated_at             | timestamp without time zone |
 email                  | character varying(255)      | not null default ''::character varying
 encrypted_password     | character varying(255)      | not null default ''::character varying
 reset_password_token   | character varying(255)      |
 reset_password_sent_at | timestamp without time zone |
 remember_created_at    | timestamp without time zone |
 sign_in_count          | integer                     | default 0
 current_sign_in_at     | timestamp without time zone |
 last_sign_in_at        | timestamp without time zone |
 current_sign_in_ip     | character varying(255)      |
 last_sign_in_ip        | character varying(255)      |
 provider               | character varying(255)      |
 uid                    | character varying(255)      |
 confirmation_token     | character varying(255)      |
 confirmed_at           | timestamp without time zone |
 unconfirmed_email      | character varying(255)      |
 confirmation_sent_at   | timestamp without time zone |
 admin                  | boolean                     | default false
 image_url              | character varying(255)      |
 total_points           | integer                     | not null default 0
 total_wins             | integer                     | not null default 0
 win_percentile         | numeric                     | not null default 0
 token_balance          | integer                     | default 0
 username               | character varying(255)      |
 fb_token               | character varying(255)      |
 inviter_id             | integer                     |
 avatar                 | character varying(255)      |
=end
    column :id
    column :name
    column :username
    column :created_at
    column :email
    column :token_balance
    column(:balance) {|u| u.customer_object.balance }
    column :rosters do |user|
      link_to "Rosters", :controller => "rosters", :action => "index", 'q[owner_id_eq]' => "#{user.id}".html_safe
    end
    column :transaction_records do |user|
      link_to "Transactions", :controller => "transaction_records", :action => "index", 'q[user_id_eq]' => "#{user.id}".html_safe
    end
    column :inviter_id
    default_actions

  end

  member_action :user_payout, :method => :post do
    user = User.find(params[:id])
    amount = params[:amount].to_i * 100
    user.customer_object.increase_account_balance(amount, 'manual_payout', :transaction_data => {reason: params[:reason] }.to_json)
    redirect_to({:action => :index}, {:notice => "User paid out successfully!"})
  end
  action_item :only => [:show, :edit] do
    form_tag(user_payout_admin_user_path(user)) do
      label_tag('form', 'Payout') + 
      text_field_tag('amount', '', :class => 'custom-text-input', :placeholder => "10.00", :maxlength => 6) + 
      text_field_tag('reason', '', :class => 'custom-text-input', :placeholder => "Why? refund for contest 187", :maxlength => 128) + 
      submit_tag("Pay them")
    end
  end
end



