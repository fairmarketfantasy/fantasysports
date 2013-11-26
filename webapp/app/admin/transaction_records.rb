ActiveAdmin.register TransactionRecord do
  filter :user_id

  index do
=begin
 id                      | integer                     | not null default nextval('transaction_records_id_seq'::regclass)
 event                   | character varying(255)      | not null
 user_id                 | integer                     | 
 roster_id               | integer                     | 
 amount                  | integer                     | 
 contest_id              | integer                     | 
 is_tokens               | boolean                     | default false
 ios_transaction_id      | character varying(255)      | 
 transaction_data        | text                        | 
 invitation_id           | integer                     | 
 referred_id             | integer                     | 
 created_at              | timestamp without time zone | 
 updated_at              | timestamp without time zone | 
 reverted_transaction_id | integer                     | 

=end
    column :id
    column :event
    column :user_id
    column :amount
    column :is_tokens
    column :roster_id
    column :transaction_data
    column :reverted_transaction
    column :invitation_id
    default_actions
  end

  member_action :user_payout, :method => :post do
    user = User.find(params[:id])
    amount = params[:use_tokens] ? params[:amount].to_i : params[:amount].to_i * 100
    user.payout(amount, params[:use_tokens], :event => 'manual_payout', :transaction_data => {reason: params[:reason]}.to_json)
    redirect_to({:action => :index}, {:notice => "User paid out successfully!"})
  end
  action_item :only => [:show, :edit] do
    form_tag(user_payout_admin_user_path(user)) do
      label_tag('form', 'Payout') + 
      text_field_tag('amount', '', :class => 'custom-text-input', :placeholder => "10.00", :maxlength => 6) + 
      text_field_tag('reason', '', :class => 'custom-text-input', :placeholder => "Why? refund for contest 187", :maxlength => 128) + 
      label_tag('use_tokens', 'As Fanfrees?', :class => 'custom-text-input', :checked => false) + 
      check_box_tag('use_tokens', '1', false) + 
      submit_tag("Pay them")
    end
  end
end




