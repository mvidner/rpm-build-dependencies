# -*- ruby -*-

YAML = "yast_deps.yaml"
file YAML do |t|
  sh "ruby", "print_deps.rb", "YaST:Head", "openSUSE_Factory", "x86_64", t.name
end
desc "Make a textual description of the dependencies and critical path"
task :deps => YAML

SVG = "yast_deps.svg"
file SVG do |t|
  sh "ruby dependson_to_graph YaST:Head openSUSE_Factory x86_64 | tred | dot -Tsvg -o #{t.name}"
end
desc "Make a SVG graph of the dependencies (requires graphviz)"
task :svg => SVG

task :default => :deps
