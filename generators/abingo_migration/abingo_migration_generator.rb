require 'rails/generators'
require 'rails/generators/active_record'
class AbingoMigrationGenerator < Rails::Generators::Base
  include Rails::Generators::Migration

  source_root File.expand_path('../templates', __FILE__)

  def self.next_migration_number(dirname) #:nodoc:
    next_migration_number = current_migration_number(dirname) + 1
    if ActiveRecord::Base.timestamped_migrations
      [Time.now.utc.strftime("%Y%m%d%H%M%S"), "%.14d" % next_migration_number].max
    else
      "%.3d" % next_migration_number
    end
  end

  def version
    Abingo.MAJOR_VERSION.gsub(".", "")
  end

  def copy_migration
    migration_template 'abingo_migration.rb', "db/migrate/abingo_migration#{version}"
  end
end
