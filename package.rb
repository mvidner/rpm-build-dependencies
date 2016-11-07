class Package
  attr_accessor :layer, :name, :depends, :time, :total_time, :size

  def initialize(name, depends, size = 0)
    @name = name
    @layer = -1
    @depends = depends
    @time = -1
    @total_time = 0
    @size = size
  end
end
