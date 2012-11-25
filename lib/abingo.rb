require "abingo/version"
require "#{File.dirname(__FILE__)}/abingo_sugar"
require "#{File.dirname(__FILE__)}/abingo_view_helper"
require "abingo/controller/dashboard"
require "abingo/rails/controller/dashboard"
require "abingo/alternative"
require "abingo/experiment"
require "#{File.dirname(__FILE__)}/../generators/abingo_migration/abingo_migration_generator.rb"
ActionController::Base.send :include, AbingoSugar
ActionView::Base.send :include, AbingoViewHelper
#This class is outside code's main interface into the ABingo A/B testing framework.
#Unless you're fiddling with implementation details, it is the only one you need worry about.

#Usage of ABingo, including practical hints, is covered at http://www.bingocardcreator.com/abingo

class Abingo
  cattr_accessor :salt
  @@salt = "Not really necessary."

  @@options ||= {}
  cattr_accessor :options

  attr_accessor :identity

  #Defined options:
  # :enable_specification  => if true, allow params[test_name] to override the calculated value for a test.
  # :enable_override_in_session => if true, allows session[test_name] to override the calculated value for a test.
  # :expires_in => if not nil, passes expire_in to creation of per-user cache keys.  Useful for Redis, to prevent expired sessions
  #               from running wild and consuming all of your memory.
  # :count_humans_only => Count only participation and conversions from humans.  Humans can be identified by calling @abingo.mark_human!
  #                       This can be done in e.g. Javascript code, which bots will typically not execute.  See FAQ for details.
  # :expires_in_for_bots => if not nil, passes expire_in to creation of per-user cache keys, but only for bots.
  #                         Only matters if :count_humans_only is on.

  #ABingo stores whether a particular user has participated in a particular
  #experiment yet, and if so whether they converted, in the cache.
  #
  #It is STRONGLY recommended that you use a MemcacheStore for this.
  #If you'd like to persist this through a system restart or the like, you can
  #look into memcachedb, which speaks the memcached protocol.  From the perspective
  #of Rails it is just another MemcachedStore.
  #
  #You can overwrite Abingo's cache instance, if you would like it to not share
  #your generic Rails cache.

  def self.cache
    @cache || ::Rails.cache
  end

  def self.cache=(cache)
    @cache = cache
  end

  def self.identity=(new_identity)
    raise RuntimeError.new("Setting identity on the class level has been deprecated. Please create an instance via: @abingo = Abingo.identify('user-id')")
  end

  def self.generate_identity
    rand(10 ** 10).to_i.to_s
  end

  #This method identifies a user and ensures they consistently see the same alternative.
  #This means that if you use Abingo.identify on someone at login, they will
  #always see the same alternative for a particular test which is past the login
  #screen.  For details and usage notes, see the docs.
  def self.identify(identity = nil)
    identity ||= generate_identity
    new(identity)
  end

  def initialize(identity)
    @identity = identity
    super
  end

  #A simple convenience method for doing an A/B test.  Returns true or false.
  #If you pass it a block, it will bind the choice to the variable given to the block.
  def flip(test_name)
    if block_given?
      yield(self.test(test_name, [true, false]))
    else
      self.test(test_name, [true, false])
    end
  end

  #This is the meat of A/Bingo.
  #options accepts
  #  :multiple_participation (true or false)
  #  :conversion  name of conversion to listen for  (alias: conversion_name)
  def test(test_name, alternatives, options = {})

    short_circuit = Abingo.cache.read("Abingo::Experiment::short_circuit(#{test_name})".gsub(" ", "_"))
    unless short_circuit.nil?
      return short_circuit  #Test has been stopped, pick canonical alternative.
    end

    unless Abingo::Experiment.exists?(test_name)
      lock_key = "Abingo::lock_for_creation(#{test_name.gsub(" ", "_")})"
      lock_id  = SecureRandom.hex
      #this prevents (most) repeated creations of experiments in high concurrency environments.
      if Abingo.cache.exist?(lock_key)
        wait_for_lock_release(lock_key)
      else
        Abingo.cache.write(lock_key, lock_id, :expires_in => 5.seconds)
        sleep(0.1)
        if Abingo.cache.read(lock_key) == lock_id
          conversion_name = options[:conversion] || options[:conversion_name]
          Abingo::Experiment.start_experiment!(test_name, Abingo.parse_alternatives(alternatives), conversion_name)
        else
          wait_for_lock_release(lock_key)
        end
      end
      Abingo.cache.delete(lock_key)
    end

    choice = self.find_alternative_for_user(test_name, alternatives)
    participating_tests = Abingo.cache.read("Abingo::participating_tests::#{self.identity}") || []

    #Set this user to participate in this experiment, and increment participants count.
    if options[:multiple_participation] || !(participating_tests.include?(test_name))
      unless participating_tests.include?(test_name)
        participating_tests = participating_tests + [test_name]
        if self.expires_in
          Abingo.cache.write("Abingo::participating_tests::#{self.identity}", participating_tests, {:expires_in => self.expires_in})
        else
          Abingo.cache.write("Abingo::participating_tests::#{self.identity}", participating_tests)
        end
      end
      #If we're only counting known humans, then postpone scoring participation until after we know the user is human.
      if (!@@options[:count_humans_only] || self.is_human?)
        Abingo::Alternative.score_participation(test_name, choice)
      end
    end

    if block_given?
      yield(choice)
    else
      choice
    end
  end

  def wait_for_lock_release(lock_key)
    while Abingo.cache.exist?(lock_key)
      sleep(0.1)
    end
  end

  #Scores conversions for tests.
  #test_name_or_array supports three types of input:
  #
  #A conversion name: scores a conversion for any test the user is participating in which
  #  is listening to the specified conversion.
  #
  #A test name: scores a conversion for the named test if the user is participating in it.
  #
  #An array of either of the above: for each element of the array, process as above.
  #
  #nil: score a conversion for every test the u
  def bingo!(name = nil, options = {})
    if name.kind_of? Array
      name.map do |single_test|
        self.bingo!(single_test, options)
      end
    else
      if name.nil?
        #Score all participating tests
        participating_tests = Abingo.cache.read("Abingo::participating_tests::#{self.identity}") || []
        participating_tests.each do |participating_test|
          self.bingo!(participating_test, options)
        end
      else #Could be a test name or conversion name.
        conversion_name = name.gsub(" ", "_")
        tests_listening_to_conversion = Abingo.cache.read("Abingo::tests_listening_to_conversion#{conversion_name}")
        if tests_listening_to_conversion
          if tests_listening_to_conversion.size > 1
            tests_listening_to_conversion.map do |individual_test|
              self.score_conversion!(individual_test.to_s)
            end
          elsif tests_listening_to_conversion.size == 1
            test_name_str = tests_listening_to_conversion.first.to_s
            self.score_conversion!(test_name_str)
          end
        else
          #No tests listening for this conversion.  Assume it is just a test name.
          test_name_str = name.to_s
          self.score_conversion!(test_name_str)
        end
      end
    end
  end

  def participating_tests(only_current = true)
    participating_tests = Abingo.cache.read("Abingo::participating_tests::#{identity}") || []
    tests_and_alternatives = participating_tests.inject({}) do |acc, test_name|
      alternatives_key = "Abingo::Experiment::#{test_name}::alternatives".gsub(" ","_")
      alternatives = Abingo.cache.read(alternatives_key)
      acc[test_name] = find_alternative_for_user(test_name, alternatives)
      acc
    end
    if (only_current)
      tests_and_alternatives.reject! do |key, value|
        Abingo.cache.read("Abingo::Experiment::short_circuit(#{key})")
      end
    end
    tests_and_alternatives
  end

  #Marks that this user is human.
  def human!
    Abingo.cache.fetch("Abingo::is_human(#{self.identity})",  {:expires_in => self.expires_in(true)}) do
      #Now that we know the user is human, score participation for all their tests.  (Further participation will *not* be lazy evaluated.)

      #Score all tests which have been deferred.
      participating_tests = Abingo.cache.read("Abingo::participating_tests::#{self.identity}") || []

      #Refresh cache expiry for this user to match that of known humans.
      if (@@options[:expires_in_for_bots] && !participating_tests.blank?)
        Abingo.cache.write("Abingo::participating_tests::#{self.identity}", participating_tests, {:expires_in => self.expires_in(true)})
      end

      participating_tests.each do |test_name|
        viewed_alternative = find_alternative_for_user(test_name,
          Abingo::Experiment.alternatives_for_test(test_name))
        Alternative.score_participation(test_name, viewed_alternative)
        if conversions = Abingo.cache.read("Abingo::conversions(#{self.identity},#{test_name}")
          conversions.times { Alternative.score_conversion(test_name, viewed_alternative) }
        end
      end
      true #Marks this user as human in the cache.
    end
  end

  def is_human?
    !!Abingo.cache.read("Abingo::is_human(#{self.identity})")
  end

  protected

  #For programmer convenience, we allow you to specify what the alternatives for
  #an experiment are in a few ways.  Thus, we need to actually be able to handle
  #all of them.  We fire this parser very infrequently (once per test, typically)
  #so it can be as complicated as we want.
  #   Integer => a number 1 through N
  #   Range   => a number within the range
  #   Array   => an element of the array.
  #   Hash    => assumes a hash of something to int.  We pick one of the
  #              somethings, weighted accorded to the ints provided.  e.g.
  #              {:a => 2, :b => 3} produces :a 40% of the time, :b 60%.
  #
  #Alternatives are always represented internally as an array.
  def self.parse_alternatives(alternatives)
    if alternatives.kind_of? Array
      return alternatives
    elsif alternatives.kind_of? Integer
      return (1..alternatives).to_a
    elsif alternatives.kind_of? Range
      return alternatives.to_a
    elsif alternatives.kind_of? Hash
      alternatives_array = []
      alternatives.each do |key, value|
        if value.kind_of? Integer
          alternatives_array += [key] * value
        else
          raise "You gave a hash with #{key} => #{value} as an element.  The value must be an integral weight."
        end
      end
      return alternatives_array
    else
      raise "I don't know how to turn [#{alternatives}] into an array of alternatives."
    end
  end

  def self.retrieve_alternatives(test_name, alternatives)
    cache_key = "Abingo::Experiment::#{test_name}::alternatives".gsub(" ","_")
    alternative_array = Abingo.cache.fetch(cache_key) do
      Abingo.parse_alternatives(alternatives)
    end
    alternative_array
  end

  def find_alternative_for_user(test_name, alternatives)
    alternatives_array = Abingo.retrieve_alternatives(test_name, alternatives)
    alternatives_array[self.modulo_choice(test_name, alternatives_array.size)]
  end

  #Quickly determines what alternative to show a given user.  Given a test name
  #and their identity, we hash them together (which, for MD5, provably introduces
  #enough entropy that we don't care) otherwise
  def modulo_choice(test_name, choices_count)
    Digest::MD5.hexdigest(Abingo.salt.to_s + test_name + self.identity.to_s).to_i(16) % choices_count
  end

  def score_conversion!(test_name)
    test_name.gsub!(" ", "_")
    participating_tests = Abingo.cache.read("Abingo::participating_tests::#{self.identity}") || []
    if options[:assume_participation] || participating_tests.include?(test_name)
      cache_key = "Abingo::conversions(#{self.identity},#{test_name}"
      if options[:multiple_conversions] || !Abingo.cache.read(cache_key)
        if !options[:count_humans_only] || is_human?
          viewed_alternative = find_alternative_for_user(test_name,
            Abingo::Experiment.alternatives_for_test(test_name))
          Abingo::Alternative.score_conversion(test_name, viewed_alternative)
        end

        if Abingo.cache.exist?(cache_key)
          Abingo.cache.increment(cache_key)
        else
          Abingo.cache.write(cache_key, 1)
        end
      end
    end
  end

  def expires_in(known_human = false)
    expires_in = nil
    if (@@options[:expires_in])
      expires_in = @@options[:expires_in]
    end
    if (@@options[:count_humans_only] && @@options[:expires_in_for_bots] && !(known_human || is_human?))
      expires_in = @@options[:expires_in_for_bots]
    end
    expires_in
  end

end
