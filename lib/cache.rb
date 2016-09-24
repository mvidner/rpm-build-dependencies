require "fileutils"

$cache_dir = nil
def cache_dir
  return $cache_dir if $cache_dir
  name = File.expand_path("../../cache", __FILE__)
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
