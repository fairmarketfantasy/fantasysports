name "testing"
description "testing environments"
cookbook_versions "aliases" => ">= 0.1.0"
override_attributes({
  "env" => {"RAILS_ENV" => "testing"}, 
  "easternpeak" => {"database" => {"master_url" => "localhost"}}
})
