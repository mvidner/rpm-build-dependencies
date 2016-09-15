require "yaml"

class Package
  attr_accessor :layer, :name, :build_deps, :runtime_deps

  def initialize(name)
    @name = name
    @layer = -1
    @build_deps = nil
    @runtime_deps = nil
  end

  def read_spec(file)
    # TODO: subpackages
    lines = IO.readlines(file)

    @build_deps = process_dep(lines, /^\s*BuildRequires:\s*(.*)$/)
    @runtime_deps = process_dep(lines, /^\s*Requires:\s*(.*)$/)
  end

  private

  def process_dep(lines, pattern)
    deps_lines = lines.grep(/^\s*BuildRequires:/)
    deps_lines.each_with_object([]) do |line, res|
      deps = line[/^\s*BuildRequires:\s*(.*)$/, 1].split
      # filter out version restriction like ">=" or "0.5.6"
      deps.delete_if { |d| d.match(/^[<=>!0-9]/) }

      res.concat(deps)
    end
  end
end

def process_files(files, packages)
  files.each do |file|
    # TODO: subpackages
    pkg_name = File.basename(file, ".spec")
    packages[pkg_name] = Package.new(pkg_name)
    packages[pkg_name].read_spec(file)
  end
end

def compute_dependencies(packages)
  dependencies = {}
  packages.each_pair do |name, pkg|
    # add to dependencies all known build requires + its runtime deps
    dependencies[name] = pkg.build_deps.each_with_object([]) do |dep, res|
      next unless packages[dep]
      res << dep
      runtime_deps = packages[dep].runtime_deps
      res.concat(runtime_deps.select{ |d| packages[d] })
    end
  end

  dependencies
end

def compute_layers(packages)
  dependencies = compute_dependencies(packages)
  current_layer = 0
  while(!dependencies.empty?) do
    pkgs_for_layer = dependencies.select{ |k,v| v.empty? }.keys
    raise "cycle detected" if pkgs_for_layer.empty?

    pkgs_for_layer.each do |pkg|
      packages[pkg].layer = current_layer
    end

    dependencies.keep_if { |k, v| !pkgs_for_layer.include?(k) }
    dependencies.each_pair { |k, v| dependencies[k] = v - pkgs_for_layer }

    current_layer += 1
  end
end

def print_yaml(output_file, packages)
  result_map = {}

  max_layer = packages.values.max_by { |p| p.layer }.layer
  result_map["layers"] = {}
  (0..max_layer).each { |l| result_map["layers"][l] = [] }

  packages.each do |name, pkg|
    result_map["layers"][pkg.layer] << name
  end

  result_map["dependencies"] = compute_dependencies(packages)
  result_map["dependencies"].each_pair { |k,v| v.map! { |d| "#{d}[#{packages[d].layer}]" } }

  File.write(output_file, result_map.to_yaml)
end

glob, output_file = ARGV

files = Dir.glob(glob)
packages = {}

process_files(files, packages)
compute_layers(packages)
print_yaml(output_file, packages)