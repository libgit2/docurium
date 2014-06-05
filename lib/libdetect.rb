require 'rbconfig'
require 'mkmf'

# This is pretty terrible, but we need to have the environment set up
# before we require the ffi-clang module.

module LibDetect

  DARWIN_LIBCLANG = '/Library/Developer/CommandLineTools/usr/lib/libclang.dylib'

  host_os = RbConfig::CONFIG['host_os']
  case host_os
  when /darwin/
    File.exist? DARWIN_LIBCLANG
    ENV['LIBCLANG'] = DARWIN_LIBCLANG
  when /linux/
    prog = 'llvm-config-3.4'
    if find_executable(prog)
      ENV['LLVM_CONFIG'] = prog
    end
  end

end
