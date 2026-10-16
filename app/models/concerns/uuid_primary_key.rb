module UuidPrimaryKey
  extend ActiveSupport::Concern

  included do
    before_create :assign_uuid, if: -> { id.blank? }
  end

  private

  def assign_uuid
    self.id = SecureRandom.uuid
  end
end
