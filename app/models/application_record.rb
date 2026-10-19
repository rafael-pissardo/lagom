class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  include UuidPrimaryKey

  self.strict_loading_by_default = true
end
