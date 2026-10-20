class YearlyReportRefreshService
  STREAM = "yearly_report"
  INTERVAL = 2

  class << self
    def call(force: false)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if !force && last && (now - last) < INTERVAL

      self.last = now
      Turbo::StreamsChannel.broadcast_refresh_to(STREAM)
    end

    def reset!
      self.last = nil
    end

    private

    attr_accessor :last
  end
end
