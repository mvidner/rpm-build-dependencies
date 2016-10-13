require "yaml"
require "cheetah"
require "pp"
require "rexml/document"
require "fileutils"
require "tmpdir"

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

$cache_dir = nil
def cache_dir
  return $cache_dir if $cache_dir
  name = File.expand_path("../cache", __FILE__)
  FileUtils.mkdir_p name unless File.directory? name
  $cache_dir = name
end

# A persistent cache for an expensive operation that returns a string.
# @param filename [String] base name of file to cache the result.
#    Will be kept in {#cache_dir}
# @param block The expensive operation
def cache(filename, &block)
  fullname = "#{cache_dir}/#{filename}"
  if File.exist?(fullname)
    File.read(fullname)
  else
    result = block.call
    File.write(fullname, result)
    result
  end
end

def osc_dependson(project, build_target, arch)
  cache("#{project}@#{build_target}@#{arch}.dependson") do
    puts "Obtaining dependson for #{project}"
    Cheetah.run "osc", "dependson", project, build_target, arch,
                stdout: :capture
  end
end

def get_packages(project, build_target, arch)
  output = osc_dependson(project, build_target, arch)
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
  need_bootstraps = dependencies.map { |k, v| v.include?(k) ? k : nil }
  need_bootstraps.compact!
  current_layer = -1
  next_pkg_for_layer = need_bootstraps
  while(!dependencies.empty?) do
    puts "remaining dependencies size #{dependencies.size}"

    pkgs_for_layer = next_pkg_for_layer
    next_pkg_for_layer = []

    pkgs_for_layer.each do |pkg|
      packages[pkg].layer = current_layer
      dependencies.delete(pkg)
    end

    dependencies.each_pair do |k, v|
      dependencies[k] = v - pkgs_for_layer
      next_pkg_for_layer << k if dependencies[k].empty?
    end

    if next_pkg_for_layer.empty? && !dependencies.empty?
      # find circular dependencies and pick anyone from it
      next_pkg_for_layer = find_circular_dependencies(dependencies)
      raise "no circular dependency found" if next_pkg_for_layer.empty?
    end

    current_layer += 1
  end
end

def find_circular_dependencies(dependencies)

  # search in depth
  indices = dependencies.each_with_object([]) do |pair, indices|
    name, deps = pair
    deps.each do |d|
      indices << [name, d]
    end
  end

  result = DirectedGraph.strongly_connected_components(indices)
  result.select!{ |i| i.size > 1 }
  puts "circular dependencies detected: #{result}"
  # pick one package from each circular dependency
  result.map(&:first)
end

# code from http://stackoverflow.com/questions/9728910/giving-an-example-of-a-cycle-in-a-directed-graph
module DirectedGraph; module_function
  ## Tarjan's algorithm
  def strongly_connected_components graph
    @index, @stack, @indice, @lowlink, @scc = 0, [], {}, {}, []
    @graph = graph
    @graph.flatten(1).uniq.each{|v| strong_connect(v) unless @indice[v]}
    @scc
  end

  def strong_connect v
    @indice[v] = @index
    @lowlink[v] = @index
    @index += 1
    @stack.push(v)
    @graph.each do |vv, w|
      next unless vv == v
      if !@indice[w]
        strong_connect(w)
        @lowlink[v] = [@lowlink[v], @lowlink[w]].min
      elsif @stack.include?(w)
        @lowlink[v] = [@lowlink[v], @indice[w]].min
      end
    end
    if @lowlink[v] == @indice[v]
      i = @stack.index(v)
      @scc.push(@stack[i..-1])
      @stack = @stack[0...i]
    end
  end
end

# Ask the OBS for the build statistics of a package
# @return [String] XML, or an empty string if there is no build
def statistics(project, package_name, target, arch)
  cache("#{project}@#{package_name}@#{target}@#{arch}.statistics.xml") do
    puts "Obtaining build time for #{package_name}"

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # return code 0 even if no files are fetched
        Cheetah.run "osc", "-v", "getbinaries",
                    project, package_name, target, arch, "_statistics"

        if File.exist? "binaries/_statistics"
          ret = File.read "binaries/_statistics"
          FileUtils.rm_rf "binaries"
          ret
        else
          ""
        end
      end
    end
  end
end

def compute_time(packages, project, target, arch)
  packages.values.each do |pkg|
    xml = statistics(project, pkg.name, target, arch)
    next if xml.empty?
    doc = REXML::Document.new(xml)
    pkg.time = doc.root.elements["times/total/time"].text.to_i
  end
end

def compute_min_time(packages)
  pkgs_by_layer = packages.values.sort_by{ |p| p.layer }
  pkgs_by_layer.each do |pkg|
    slowest_dep = pkg.depends.max_by { |p| packages[p].total_time }
    dep_time = slowest_dep ? packages[slowest_dep].total_time : 0
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
