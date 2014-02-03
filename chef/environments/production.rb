name "production"
description "production environments"
cookbook_versions "aliases" => ">= 0.1.0"
override_attributes "env" => {"RAILS_ENV" => "production"}

