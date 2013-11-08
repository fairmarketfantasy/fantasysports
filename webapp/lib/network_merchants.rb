=begin
builder = Nokogiri::XML::Builder.new do |xml|
xml.root {
  xml.products {
    xml.widget {
      xml.id_ "10"
      xml.name "Awesome widget"
    }
  }
}
end
puts builder.to_xml


4111111111111111
341111111111111

=end

class StupidXmlObject
  def initialize(body)
    @xml = Nokogiri::XML(body)
  end

  def[](attr)
    begin
      @xml.xpath("//#{attr}").children.first.content
    rescue StandardError => e
      raise "No such simple attribute: #{attr}"
    end
  end

  def method_missing(attr)
    self[attr]
  end
end

class NetworkMerchants
  API_KEY = 'YHegj6R6JVK3Z897VxC6dc5GRN5N478c'
  TEST_API_KEY = '2F822Rw39fx762MaV7Yy86jXGTC7sCDy'
  API_ENDPOINT = 'https://secure.nmi.com/api/v2/three-step'
  
  def self.add_customer_form(callbackName)
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.send("add-customer") {
        xml.send("api-key", Rails.env == 'production' ? API_KEY : TEST_API_KEY)
        xml.send("redirect-url", SITE + "/cards/token_redirect_url?callback=#{callbackName}")
      }
    end
    resp = Typhoeus.post(API_ENDPOINT, headers: headers, body: builder.to_xml)
    StupidXmlObject.new(resp.body)['form-url']
# form-url
# result-code
# result-text
  end

  def self.add_customer_finalize(customer_object, token_id)
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.send("complete-action") {
        xml.send("api-key", Rails.env == 'production' ? API_KEY : TEST_API_KEY)
        xml.send("token-id", token_id)
      }
    end
    resp = Typhoeus.post(API_ENDPOINT, headers: headers, body: builder.to_xml)
    xml = StupidXmlObject.new(resp.body)
    raise "Card not approved" if xml['result-text'] != 'OK'
# [ "result",  "result-text",  "action-type",  "result-code",  "amount",  "customer-id",  "customer-vault-id",  "billing",  "shipping", "text"]
    card = CreditCard.create!(
      :customer_object_id => customer_object.id,
      :obscured_number => xml['cc-number'],
      :expires => Time.new( 2000 + xml['cc-exp'][2..3].to_i, xml['cc-exp'][0..1].to_i),
      :first_name => (xml['first-name'] rescue ''),
      :last_name => (xml['last-name'] rescue ''),
      :network_merchant_id => xml['customer-vault-id'],
    )
      customer_object.default_card = card
      customer_object.save!
  end

  def self.finalize_customer(token_id)
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.send("complete-action") {
        xml.send("api-key", Rails.env == 'production' ? API_KEY : TEST_API_KEY)
        xml.send("token-id", token_id)
      }
    end
    resp = Typhoeus.post(API_ENDPOINT, headers: headers, body: builder.to_xml)
    Nokogiri::XML(resp.body)
  end

  def self.headers
    {'Content-type' => 'text/xml'}
  end
end
