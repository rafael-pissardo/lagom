module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        user = request.env["warden"]&.user
        self.current_user = user if user
      end
  end
end
