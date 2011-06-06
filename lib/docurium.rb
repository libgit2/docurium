require 'pp'

class Docurium
  Version = VERSION = '0.0.1'

  attr_accessor :header_dir, :branch, :output_dir, :valid, :data

  def initialize(dir)
    @valid = false
    @data = {}
    if !dir
      puts "You need to specify a directory"
    else
      @valid = true
      @header_dir = dir
    end
  end

  def set_branch(branch)
    @branch = branch
  end

  def set_output_dir(dir)
    @output_dir = dir
  end

  def generate_docs
    puts "generating docs from #{@header_dir}"
    Dir.chdir(@header_dir) do
      Dir.glob(File.join('**/*.h')).each do |header|
        next if !File.file?(header)
        puts "  - processing #{header}"
        parse_header(header)
      end
    end
    if @branch
      write_branch
    else
      write_dir
    end
  end

  private

  def parse_header(filepath)
    in_comment = false
    current = -1
    lineno = 0
    data = []
    File.readlines(filepath).each do |line|
      lineno += 1
      line = line.strip
      next if line.size == 0

      if m = /(.*?)\/\*(.*?)\*\//.match(line)
        code = m[1]
        comment = m[2]
        current += 1
        data[current] ||= {:comments => [comment], :code => [code], :line => lineno}
      elsif m = /(.*?)\/\/(.*?)/.match(line)
        code = m[1]
        comment = m[2]
        current += 1
        data[current] ||= {:comments => [comment], :code => [code], :line => lineno}
      else
        if line =~ /\/\*/
          in_comment = true  
          current += 1
        end
        data[current] ||= {:comments => [], :code => [], :line => lineno}
        if in_comment
          data[current][:comments] << line
        else
          data[current][:code] << line
        end
        in_comment = false if line =~ /\*\//
      end
    end
    meta  = extract_meta(data)
    funcs = extract_functions(data)
    @data[filepath] = {:meta => meta, :functions => funcs}
  end

  # go through all the comment blocks and extract:
  #  @file, @brief, @defgroup and @ingroup
  def extract_meta(data)
    file, brief, defgroup, ingroup = nil
    data.each do |block|
      block[:comments].each do |comment|
        m = []
        file  = m[1] if m = /@file (.*?)$/.match(comment)
        brief = m[1] if m = /@brief (.*?)$/.match(comment)
        defgroup = m[1] if m = /@defgroup (.*?)$/.match(comment)
        ingroup  = m[1] if m = /@ingroup (.*?)$/.match(comment)
      end
    end
    {:file => file, :brief => brief, :defgroup => defgroup, :ingroup => ingroup}
  end

  def extract_functions(data)
    funcs = []
    data.each do |block|
      ignore = false
      block[:code].each do |line|
        next if ignore
        if m = /(.*?) ([a-z_]+)\((.*)\)/.match(line)
          ret  = m[1]
          fun  = m[2]
          args = m[3]
          funcs << [ret, fun, args, block[:line], block[:comments]]
        end
        ignore = true if line =~ /\{/
      end
    end
    funcs
  end

  def write_branch
    puts "Writing to branch #{@branch}"
    puts "Done!"
  end

  def write_dir
    output_dir = @output_dir || 'docs'
    puts "Writing to directory #{output_dir}"

    # files
    # modules
    #
    # functions
    # variables
    # defines
    # enums
    # typedefs
    # data structures
    #
    @data.each do |path, d|
      puts '---'
      puts path
      pp d[:meta]
      pp d[:functions]
    end
    puts "Done!"
  end
end
