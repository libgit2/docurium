require 'minitest/autorun'
require 'docurium'
require 'docurium/cli'
require 'tempfile'

class GenTest < MiniTest::Unit::TestCase

  # make sure we can read what we give the user
  def test_read_generated_file
    file = Tempfile.new 'docurium'
    capture_io do
      Docurium::CLI.gen(file.path)
    end

    assert_raises(Rugged::RepositoryError) { Docurium.new file.path }
  end

end
