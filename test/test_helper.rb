#require 'rubygems'
#require 'rails'
#
#require 'rails/all'
require 'test/unit'
require 'contest'
require 'sqlite3'
require 'active_support/cache'
require 'active_support/cache/memory_store'
require_relative '../lib/abingo'
ActiveRecord::Base.establish_connection(
  :adapter => "sqlite3",
  :dbfile  => ":memory:",
  :database => "abingo-test")
ActiveRecord::Schema.define do
  create_table "experiments", :force => true do |t|
    t.string "test_name"
    t.string "status"
    t.timestamps
  end

  add_index "experiments", "test_name"
  #add_index "experiments", "created_on"

  create_table "alternatives", :force => true do |t|
    t.integer :experiment_id
    t.string :content
    t.string :lookup, :limit => 32
    t.integer :weight, :default => 1
    t.integer :participants, :default => 0
    t.integer :conversions, :default => 0
  end

  add_index "alternatives", "experiment_id"
  add_index "alternatives", "lookup"  #Critical for speed, since we'll primarily be updating by that.
end
Abingo.cache = ActiveSupport::Cache::MemoryStore.new
#
#require 'active_support'
#require 'active_support/railtie'
#require 'active_support/core_ext'
#require 'active_support/test_case'
#
#require 'action_controller'
#require 'action_controller/caching'
#require 'active_record'
#require 'active_record/base'
#
#require 'rails'
#require 'rails/application'
#
#require 'rails/railtie'
#
##We need to load the whole Rails application to properly initialize Rails.cache and other constants.  Oh boy.
##We're going to parse it out of RAILS_PATH/config.ru using a little metaprogramming magic.
#require ::File.expand_path('../../../../../config/environment',  __FILE__)
#lines = File.open(::File.expand_path('../../../../../config.ru',  __FILE__)).readlines.select {|a| a =~ /::Application/}
#application_name = lines.first[/[^ ]*::/].gsub(":", "")
#Kernel.const_get(application_name).const_get("Application").initialize!
#
