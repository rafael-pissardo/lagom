module Finance
  class Amount
    CENTS_PER_EURO = 100

    def self.from_decimal_string(value)
      raise ArgumentError, "amount is blank" if value.nil? || value.to_s.strip.empty?

      normalized = value.to_s.strip.tr(",", ".")
      raise ArgumentError, "amount is invalid" unless normalized.match?(/\A-?\d+(\.\d+)?\z/)

      negative = normalized.start_with?("-")
      absolute = normalized.delete_prefix("-")
      whole, fraction = absolute.split(".", 2)
      fraction ||= ""
      truncated = (whole.to_i * CENTS_PER_EURO) + fraction.ljust(2, "0")[0, 2].to_i
      remainder = fraction.length > 2 && !fraction[2..].match?(/\A0*\z/)
      cents = !negative && remainder ? truncated + 1 : truncated
      negative ? -cents : cents
    end

    def self.percentage_ceil(cents, numerator, denominator)
      raise ArgumentError, "cents must be non-negative" if cents.negative?
      raise ArgumentError, "denominator must be positive" if denominator <= 0

      (cents * numerator).ceildiv(denominator)
    end

    def self.format_euros(cents)
      sign = cents.negative? ? "-" : ""
      absolute = cents.abs
      euros = absolute / CENTS_PER_EURO
      remainder = absolute % CENTS_PER_EURO
      grouped = euros.to_s.gsub(/\B(?=(\d{3})+(?!\d))/, ",")
      format("%s%s.%02d €", sign, grouped, remainder)
    end
  end
end
