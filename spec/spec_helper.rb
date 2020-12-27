require "bundler/setup"
require "natural_20"
require "pry-byebug"

def auto_build_self(source, session, action_class, build_opts = {})
  cont = action_class.build(session, source)
  begin
    param = cont.param&.map { |p|
      raise "param not specified #{p[:type]}" unless build_opts[p[:type]]
      build_opts[p[:type]]
    }
    cont = cont.next.call(*param)
  end while !param.nil?
  cont
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
