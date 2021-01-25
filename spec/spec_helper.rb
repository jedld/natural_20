# typed: true
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

RSpec::Matchers.define :be_a_hash_like do |expected_hash|
  match do |actual_hash|
    matching_results = actual_hash == expected_hash
    unless matching_results
      system(
        "git diff $(echo '#{JSON.pretty_generate(expected_hash)}' | git hash-object -w --stdin) " +
                 "$(echo '#{JSON.pretty_generate(actual_hash)}' | git hash-object -w --stdin) --word-diff",
        out: $stdout,
        err: :out
      )
    end
    matching_results
  end

  failure_message { 'Look at the Diff above! ^^^' }
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
