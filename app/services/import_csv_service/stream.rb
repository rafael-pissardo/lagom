class ImportCsvService::Stream
  def initialize(io)
    @io = io
    @prefix_checked = false
  end

  def gets(...)
    chunk = io.gets(...)
    return if chunk.nil?

    validate_chunk!(chunk)
    chunk
  end

  def eof?
    io.eof?
  end

  def rewind
    @prefix_checked = false
    io.rewind
  end

  private

  attr_reader :io

  def validate_chunk!(chunk)
    text = chunk.dup.force_encoding(Encoding::UTF_8)
    raise ImportCsvService::InvalidFile, "CSV is not valid UTF-8" unless text.valid_encoding?

    unless @prefix_checked
      @prefix_checked = true
      if text.b.start_with?(ImportCsvService::BOM)
        raise ImportCsvService::InvalidFile, "CSV contains characters outside the SeQura files"
      end
    end

    return if text.match?(ImportCsvService::ALLOWED_CHARACTERS)

    raise ImportCsvService::InvalidFile, "CSV contains characters outside the SeQura files"
  end
end
