require_relative "statistics"
require_relative "conversion_rate"
class BananaSplit::Experiment < ActiveRecord::Base
  include BananaSplit::Statistics
  include BananaSplit::ConversionRate

  has_many :alternatives, :dependent => :destroy, :class_name => "BananaSplit::Alternative"
  validates_uniqueness_of :test_name
  attr_accessible :test_name
  before_destroy :cleanup_cache

  def cache_keys
  ["BananaSplit::Experiment::exists(#{test_name})".gsub(" ", "_"),
    "BananaSplit::Experiment::#{test_name}::alternatives".gsub(" ","_"),
    "BananaSplit::Experiment::short_circuit(#{test_name})".gsub(" ", "_")
  ]
  end

  def cleanup_cache
    cache_keys.each do |key|
      BananaSplit.cache.delete key
    end
    true
  end

  def participants
    alternatives.sum("participants")
  end

  def conversions
    alternatives.sum("conversions")
  end

  def best_alternative
    alternatives.max do |a,b|
      a.conversion_rate <=> b.conversion_rate
    end
  end

  def self.exists?(test_name)
    cache_key = "BananaSplit::Experiment::exists(#{test_name})".gsub(" ", "_")
    ret = BananaSplit.cache.fetch(cache_key) do
      count = BananaSplit::Experiment.where(test_name: test_name).count
      count > 0 ? count : nil
    end
    (!ret.nil?)
  end

  def self.alternatives_for_test(test_name)
    cache_key = "BananaSplit::#{test_name}::alternatives".gsub(" ","_")
    BananaSplit.cache.fetch(cache_key) do
      experiment = BananaSplit::Experiment.find_by_test_name(test_name)
      alternatives_array = BananaSplit.cache.fetch(cache_key) do
        tmp_array = experiment.alternatives.map do |alt|
          [alt.content, alt.weight]
        end
        tmp_hash = tmp_array.inject({}) {|hash, couplet| hash[couplet[0]] = couplet[1]; hash}
        BananaSplit.parse_alternatives(tmp_hash)
      end
      alternatives_array
    end
  end

  def self.start_experiment!(test_name, alternatives_array, conversion_name = nil)
    conversion_name ||= test_name
    conversion_name.gsub!(" ", "_")
    cloned_alternatives_array = alternatives_array.clone
    ActiveRecord::Base.transaction do
      experiment = BananaSplit::Experiment.find_or_create_by(test_name: test_name)
      experiment.alternatives.destroy_all  #Blows away alternatives for pre-existing experiments.
      while (cloned_alternatives_array.size > 0)
        alt = cloned_alternatives_array[0]
        weight = cloned_alternatives_array.size - (cloned_alternatives_array - [alt]).size
        experiment.alternatives.build(:content => alt, :weight => weight,
          :lookup => BananaSplit::Alternative.calculate_lookup(test_name, alt))
        cloned_alternatives_array -= [alt]
      end
      experiment.status = "Live"
      experiment.save(:validate => false)
      BananaSplit.cache.write("BananaSplit::Experiment::exists(#{test_name})".gsub(" ", "_"), 1)

      #This might have issues in very, very high concurrency environments...

      tests_listening_to_conversion = BananaSplit.cache.read("BananaSplit::tests_listening_to_conversion#{conversion_name}") || []
      tests_listening_to_conversion += [test_name] unless tests_listening_to_conversion.include? test_name
      BananaSplit.cache.write("BananaSplit::tests_listening_to_conversion#{conversion_name}", tests_listening_to_conversion)
      experiment
    end
  end

  def end_experiment!(final_alternative, conversion_name = nil)
    conversion_name ||= test_name
    ActiveRecord::Base.transaction do
      alternatives.each do |alternative|
        alternative.lookup = "Experiment completed.  #{alternative.id}"
        alternative.save!
      end
      update_attribute(:status, "Finished")
      BananaSplit.cache.write("BananaSplit::Experiment::short_circuit(#{test_name})".gsub(" ", "_"), final_alternative)
    end
  end

end
