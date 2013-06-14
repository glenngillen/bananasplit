require "minitest/autorun"
require "sequel"
ENV["DATABASE_URL"] = "postgres://localhost/bananasplit-test"
Sequel.extension :migration

def setup_database
  Sequel::Migrator.apply(Sequel.connect(ENV["DATABASE_URL"]), './db/migrations', 0)
  Sequel::Migrator.apply(Sequel.connect(ENV["DATABASE_URL"]), './db/migrations')
end
setup_database
