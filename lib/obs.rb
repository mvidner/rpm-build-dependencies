
require "cheetah"
require "fileutils"
require "tmpdir"
require "rexml/document"
require "yaml"

require "cache"

# Open Build Service
module OBS

  # A (project, build target, architecture) triple
  # Eg. (YaST:Head, openSUSE_Factory, x86_64)
  class Project3
    # @return [String]
    attr_accessor :project
    # @return [String]
    attr_accessor :target
    # @return [String]
    attr_accessor :arch

    def initialize(project, target, arch)
      @project = project
      @target = target
      @arch = arch
    end

    def to_s
      "#{project}@#{target}@#{arch}"
    end

    # @return [Hash{String => Array<String>}] packages and their dependencies
    def dependson
      YAML.load(osc_dependson)
    end

    # @return [Integer,nil] time in seconds, or nil for unknown
    def total_build_time(package_name)
      xml = osc_statistics(package_name)
      return nil if xml.empty?
      doc = REXML::Document.new(xml)
      doc.root.elements["times/total/time"].text.to_i
    end
    
    private

    # @return [String] a dependency hash as a yaml string
    def osc_dependson
      txt = cache("#{self}.dependson") do
        puts "Obtaining dependson for #{self}"
        Cheetah.run "osc", "dependson",
        project, target, arch,
        stdout: :capture
      end
      cache("#{self}.dependson.yaml") do
        # convert to YAML!
        txt.gsub(" :", ":")               # hash keys
          .gsub(/^   /, "- ")             # list items
          .gsub(/:\n([^-])/, ": []\n\\1") # empty lists
      end
    end


    # Ask the OBS for the build statistics of a package
    # @return [String] XML, or an empty string if there is no build
    def osc_statistics(package_name)
      cache("#{package_name}@#{self}.statistics.xml") do
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
  end
end
