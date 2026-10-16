class CsvImportsController < ApplicationController
  def index
    @csv_imports = CsvImport.order(created_at: :desc).limit(50)
  end

  def new
    @csv_import = CsvImport.new
  end

  def create
    @csv_import = CsvImport.new(status: "pending")
    @csv_import.merchants_file.attach(params.require(:csv_import)[:merchants_file])
    @csv_import.orders_file.attach(params.require(:csv_import)[:orders_file])

    if @csv_import.merchants_file.attached? && @csv_import.orders_file.attached? && @csv_import.save
      ImportCsvJob.perform_later(@csv_import.id)
      redirect_to @csv_import, notice: t("csv_imports.create.notice")
    else
      flash.now[:alert] = t("csv_imports.create.alert")
      render :new, status: :unprocessable_content
    end
  end

  def show
    @csv_import = CsvImport.find(params[:id])
  end
end
