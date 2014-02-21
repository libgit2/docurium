require 'minitest/autorun'
require 'docurium'
require 'docurium/cli'
require 'tempfile'

class GenTest < MiniTest::Unit::TestCase

  # make sure we can read what we give the user
  def test_read_generated_file
    file = Tempfile.new 'docurium'
    Docurium::CLI.gen(file.path)

    Docurium.new file.path
  end

end
