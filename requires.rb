require "cheetah"
require "tmpdir"
require 'tempfile'
require "pp"
require "rexml/document"
require "fileutils"
require "./package"

class Requires

  # Returning all package installation requirements of given packages.
  # @param package_list [Array<String>] 
  # @param repo [String] OBS installation repository
  # @return [Hash] package installation requirements 
  def self.installation_requires(package_list, repo)
    packages = {}
    needed_packages = []
    package_list.each do |package_name|
      puts "Calculating installation requirements for: #{package_name}"
      packages[package_name] = package_installation_requires(package_name, repo)

      # Removing cycles
      packages[package_name].depends.reject! { |req| packages.keys.include?(req) }

      needed_packages |= packages[package_name].depends
    end

    # generating entries for packages which are not in the
    # given package list
    (needed_packages - package_list).each do |pack|
      packages[pack] = Package.new(pack, [])
    end
    packages
  end

  # Writing package dependencies to PNG file
  # @param package_list [Array<Package>] 
  # @param filename [String] filename with path
  def self.write_png(package_list, filename)
    all_needed_packages = []
    # Packages which are needed by EVERY package
    system_packages = package_list.values[0].depends
    package_list.each do |key,p|
      all_needed_packages |= p.depends
      system_packages &= p.depends if !p.depends.empty?
    end
    all_needed_packages = all_needed_packages.to_set ^ system_packages.to_set

    # Removing all not needed entries which also have empty requirements
    package_list.each do |key,p|
      # Removing system packages which will be needed by EVERY package
      p.depends = p.depends - system_packages
      if p.depends.empty? && !all_needed_packages.include?(key)
        package_list.delete(key)
      end
    end

    dot = ""
    dot << "digraph g {\n"
    dot << "rankdir=LR;\n"
    package_list.each do |key, package|
      dot << "\"#{key}\"[];\n"
      package.depends.sort.each do |request|
        dot << "\"#{key}\" -> \"#{request}\";\n"
      end
    end
    dot << "}\n"
    tmpfile = Tempfile.new('dot')
    tmpfile.write(dot)
    tmpfile.close
    system "/usr/bin/tred #{tmpfile.path} | /usr/bin/dot -Tpng -o #{filename}"
  end

  # Checking if all needed packages are installed.
  def self.check_environment
    rpm_name = "kiwi"
    begin
      Cheetah.run "rpm", "-qi", rpm_name
    rescue
      puts "Installing additional package #{rpm_name}"
      zypper_install(rpm_name)
    end
  end

private

  # Returning all package installation requirements of a given package.
  # @param package_name [String] 
  # @param repo [String] OBS installation repository
  def self.package_installation_requires(package_name, repo)
    dir = Dir.tmpdir + "/__deptest/"
    FileUtils.mkdir_p dir
    xml_doc = "<?xml version='1.0' encoding='utf-8'?>
<image schemaversion='6.1' name='dependency-test'>
<description type='system'>
<author>get_require</author>
<contact>nobody@suse.com</contact>
<specification>
test package dependency tree
</specification>
</description>
<preferences>
<type image='tbz'/>
<version>1.42.1</version>
<packagemanager>zypper</packagemanager>
</preferences>
<repository type='yast2'>
<source path='#{repo}'/>
</repository>
<packages type='bootstrap'>
<package name='#{package_name}'/>
</packages>
</image>"
    requires = []
    File.open(File.join(dir,"config.xml"), "w") { |file| file.write(xml_doc) }
    begin
      xml = Cheetah.run("sudo", "/usr/sbin/kiwi", "--info", dir, "--select",
              "packages", "--logfile", "/dev/null", :stdout => :capture)
      # remove first two lines which are not XML formated
      xml = xml.split("\n")[2..-1].join("\n")
      doc = REXML::Document.new(xml)

      doc.elements.each("*/package") { |package| requires << package.attributes["name"] }
      # remove zypper (due kiwi) and package_name
      requires.reject! { |req| ["zypper", package_name].include?(req) }
    rescue
      puts "Cannot evalutate dependencies of package: #{package_name}"
    end
    FileUtils.rm_rf dir
    
    Package.new(package_name, requires)
  end

  # Install a package using Zypper
  #
  def zypper_install(packages)
    parts = [
      "sudo",
      "zypper",
      "--non-interactive",
      "install",
      "--auto-agree-with-licenses",
      "--name"
    ]
    candidates = Array(packages)
    to_install = candidates.select do |name|
      begin
        Cheetah.run "rpm", "-qi", name
        false
      rescue
        true
      end
    end
    if to_install.empty?
      puts "All needed packages were already installed (#{candidates.join(" ")})"
    else
      puts "Installing: #{to_install.join(" ")}"
      Cheetah.run(parts + to_install)
    end
  end

end
