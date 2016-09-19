require "yaml"
require "cheetah"
require "pp"
require "rexml/document"

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

def get_packages(project, build_target, arch)
  output = Cheetah.run "osc", "dependson", project, build_target, arch, stdout: :capture
  res = {}
  current_pkg = nil
  current_deps = []
  output.lines.each do |line|
    case line
    when /^(\S+) :$/
      res[current_pkg] = Package.new(current_pkg, current_deps) if current_pkg
      current_pkg = $1
      current_deps = []
    when /^\s+(\S+)$/
      current_deps << $1
    else
      raise "unknown line '#{line}'"
    end
  end

  res[current_pkg] = Package.new(current_pkg, current_deps) if current_pkg

  res
end

def compute_layers(packages)
  dependencies = Hash[packages.values.map{ |p| [p.name, p.depends]}]
  current_layer = 0
  while(!dependencies.empty?) do
    pkgs_for_layer = dependencies.select{ |k,v| v.empty? }.keys

    pkgs_for_layer.each do |pkg|
      packages[pkg].layer = current_layer
    end

    dependencies.keep_if { |k, v| !pkgs_for_layer.include?(k) }
    dependencies.each_pair { |k, v| dependencies[k] = v - pkgs_for_layer }

    current_layer += 1
  end
end

def compute_time(packages, project, target, arch)
  Dir.chdir("/tmp") do
    packages.values.each do |pkg|
      puts "Obtaining build time for #{pkg.name}"
      Cheetah.run "osc", "-v", "getbinaries", project, pkg.name, target, arch, "_statistics"
      next unless File.exist? "/tmp/binaries/_statistics"
      doc = REXML::Document.new File.read("/tmp/binaries/_statistics")
      pkg.time = doc.root.elements["times/total/time"].text.to_i
      Cheetah.run "rm", "-rf", "binaries"
    end
  end
end

def compute_min_time(packages)
  pkgs_by_layer = packages.values.sort_by{ |p| p.layer }
  pkgs_by_layer.each do |pkg|
    slowest_dep = pkg.depends.max_by { |p| packages[p].time }
    dep_time = slowest_dep ? packages[slowest_dep].time : 0
    pkg.total_time = dep_time + pkg.time
  end
end

def print_yaml(output_file, packages)
  result_map = {}

  result_map["critical path"] = {}
  critical_pkg = packages.values.max_by { |p| p.total_time }
  result_map["critical path"]["total time"] = critical_pkg.total_time
  result_deps = []
  to_process = critical_pkg
  while(to_process) do
    result_deps << "#{to_process.name} [#{to_process.time}s]"
    next_dep = to_process.depends.max_by { |p| packages[p].total_time }
    to_process = next_dep ? packages[next_dep] : nil
  end
  result_map["critical path"]["path"] = result_deps

  max_layer = packages.values.max_by { |p| p.layer }.layer
  result_map["layers"] = {}
  (0..max_layer).each { |l| result_map["layers"][l] = [] }

  packages.each do |name, pkg|
    result_map["layers"][pkg.layer] << name
  end

  result_map["dependencies"] = Hash[packages.values.map { |p| ["#{p.name} ~ #{p.time}s", p.depends.map { |d| "#{d} [#{packages[d].layer}]" }]}]

  File.write(output_file, result_map.to_yaml)
end

project, target, arch, output_file = ARGV

raise "Usage: $0 <obs_project> <obs_build_target> <arch> <output_file>" unless output_file

packages = get_packages(project, target, arch)

compute_layers(packages)
compute_time(packages, project, target, arch)
compute_min_time(packages)
print_yaml(output_file, packages)
