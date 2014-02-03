name "staging"
description "staging environments"
cookbook_versions "aliases" => ">= 0.1.0"
override_attributes({
  "env" => {"RAILS_ENV" => "staging"}, 
  "mustwin" => {"database" => {"master_url" => "localhost"}}
})
