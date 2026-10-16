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
      fraction = (fraction || "").ljust(2, "0")[0, 2]
      cents = (whole.to_i * CENTS_PER_EURO) + fraction.to_i
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
      format("%s%d.%02d €", sign, euros, remainder)
    end
  end
end
