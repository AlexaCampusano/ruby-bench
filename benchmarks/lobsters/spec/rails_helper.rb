# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] ||= 'test'

# ruby-bench carries a frozen Lobsters snapshot with a prebuilt SQLite database.
# Loading db/schema.rb under the newer Rails used by this benchmark trips over
# MySQL-era schema options (for example, `unsigned: true`), so seed the test DB
# from the checked-in benchmark DB instead of asking Rails to rebuild it.
require 'fileutils'
production_db = File.expand_path('../db/production.sqlite3', __dir__)
test_db = File.expand_path('../db/test.sqlite3', __dir__)
FileUtils.cp(production_db, test_db) if File.exist?(production_db)

require File.expand_path("../../config/environment", __FILE__)
require 'rspec/rails'
require 'simplecov'

SimpleCov.start 'rails'
# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[Rails.root.join("spec/support/**/*.rb")].sort.each {|f| require f }

RSpec.configure do |config|
  # ## Mock Framework
  #
  # If you prefer to use mocha, flexmock or RR, uncomment the appropriate line:
  #
  # config.mock_with :mocha
  # config.mock_with :flexmock
  # config.mock_with :rr

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  # config.fixture_path = "#{::Rails.root}/spec/fixtures"

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with :truncation

    c = Category.create! category: "category1"
    c.tags.create!([{ tag: "tag1" }, { tag: "tag2" }])
  end

  config.before(:example) do
    DatabaseCleaner.start
  end

  config.after(:example) do
    DatabaseCleaner.clean
    # Admitted a little hacky. prod memoizes to save db hits but tests recreate.
    InactiveUser.instance_variable_set(:@inactive_user, nil)
  end

  config.before(:example, :js) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:example, :truncate) do
    DatabaseCleaner.strategy = :truncation
  end

  # If true, the base class of anonymous controllers will be inferred
  # automatically. This will be the default behavior in future versions of
  # rspec-rails.
  config.infer_base_class_for_anonymous_controllers = false

  config.infer_spec_type_from_file_location!
  config.raise_errors_for_deprecations!

  config.include AuthenticationHelper::FeatureHelper, type: :feature
  config.include AuthenticationHelper::RequestHelper, type: :request

  config.filter_rails_from_backtrace!
  config.filter_gems_from_backtrace \
    'bullet',
    'capybara',
    'rack',
    'rack-test',
    'railties',
    'scout_apm_ruby'
end

RSpec::Expectations.configuration.on_potential_false_positives = :nothing

# Intentionally do not call ActiveRecord::Migration.maintain_test_schema! here;
# see the test database bootstrap above.
