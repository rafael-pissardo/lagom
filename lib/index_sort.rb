class IndexSort
  attr_reader :column, :direction

  def initialize(params, columns:, fallback:)
    @columns = columns
    @fallback = fallback
    requested = params[:sort].to_s

    if columns.key?(requested)
      @column = requested
      @direction = params[:direction].to_s.casecmp("desc").zero? ? "desc" : "asc"
      @explicit = true
    else
      @column = fallback.fetch(:column)
      @direction = fallback.fetch(:direction)
      @explicit = false
    end
  end

  def apply(relation)
    return relation.reorder(@fallback.fetch(:order)) unless @explicit

    target = @columns.fetch(@column)
    if target.is_a?(Symbol)
      relation.reorder(target => @direction, id: :asc)
    else
      relation.reorder(target.call(@direction)).order(id: :asc)
    end
  end
end
