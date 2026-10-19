class CsvImportsController < ApplicationController
  SORTS = {
    "status" => :status,
    "kind" => :kind,
    "imported" => :imported_count,
    "failed" => :failed_count,
    "created_at" => :created_at
  }.freeze

  def index
    started_on = date_param(:started_on)

    csv_imports = CsvImport.all
    csv_imports = csv_imports.where(status: params[:status]) if params[:status].present?
    csv_imports = csv_imports.where(kind: params[:kind]) if params[:kind].present?
    csv_imports = csv_imports.where(created_at: started_on.all_day) if started_on

    @sort = IndexSort.new(params, columns: SORTS, fallback: { column: "created_at", direction: "desc", order: { created_at: :desc } })
    @pagy, @csv_imports = pagy(:offset, @sort.apply(csv_imports))
  end

  def new
    @csv_import = CsvImport.new
  end

  def create
    @csv_import = CsvImport.new(kind: csv_import_params[:kind], status: "processing")
    return render_invalid unless import_ready?

    @csv_import.object_key = CsvImport.object_key_for(@csv_import.kind)
    Bucket.put(key: @csv_import.object_key, body: csv_import_params[:file])

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

    response.headers["Cache-Control"] = "no-store"
    response.headers["ETag"] = %("#{SecureRandom.hex}")

    send_data csv_import.errors_txt,
      filename: "#{csv_import.object_key}.errors.txt",
      type: "text/plain",
      disposition: "attachment"
  end

  private

  def csv_import_params
    params.expect(csv_import: [ :kind, :file ])
  end

  def import_ready?
    known_kind = CsvImport.kinds.key?(csv_import_params[:kind].to_s)
    @csv_import.errors.add(:kind, :inclusion) unless known_kind
    @csv_import.errors.add(:file, :blank) if csv_import_params[:file].blank?
    known_kind && csv_import_params[:file].present?
  end

  def render_invalid
    flash.now[:alert] = t("csv_imports.create.alert")
    render :new, status: :unprocessable_content
  end
end
