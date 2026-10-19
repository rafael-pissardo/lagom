class CsvImportsController < ApplicationController
  def index
    @csv_imports = CsvImport.order(created_at: :desc).limit(50)
  end

  def new
    @csv_import = CsvImport.new
  end

  def create
    @csv_import = CsvImport.new(kind: kind_param, status: "processing")
    return render_invalid unless import_ready?

    @csv_import.object_key = CsvImport.object_key_for(@csv_import.kind)
    Bucket.put(key: @csv_import.object_key, body: file_param)

    if @csv_import.save
      ImportCsvJob.perform_later(@csv_import.id)
      redirect_to @csv_import, notice: t("csv_imports.create.notice")
    else
      render_invalid
    end
  rescue Bucket::Error
    render_invalid
  end

  def show
    @csv_import = CsvImport.find(params[:id])
  end

  def errors
    csv_import = CsvImport.find(params[:id])
    return head :not_found unless csv_import.failed? && csv_import.error_rows.any?

    send_data csv_import.errors_txt,
      filename: "#{csv_import.object_key}.errors.txt",
      type: "text/plain",
      disposition: "attachment"
  end

  private

  def kind_param
    params.dig(:csv_import, :kind).to_s
  end

  def file_param
    params.dig(:csv_import, :file)
  end

  def import_ready?
    known_kind = CsvImport::KINDS.include?(kind_param)
    @csv_import.errors.add(:kind, :inclusion) unless known_kind
    @csv_import.errors.add(:file, :blank) if file_param.blank?
    known_kind && file_param.present?
  end

  def render_invalid
    flash.now[:alert] = t("csv_imports.create.alert")
    render :new, status: :unprocessable_content
  end
end
