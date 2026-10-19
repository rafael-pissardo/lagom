class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  self.strict_loading_by_default = true
end
