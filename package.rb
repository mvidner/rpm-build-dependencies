class Package
  attr_accessor :layer, :name, :depends, :time, :total_time

  def initialize(name, depends)
    @name = name
    @layer = -1
    @depends = depends
    @time = -1
    @total_time = 0
  end
end
