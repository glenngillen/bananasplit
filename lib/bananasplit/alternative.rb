require "active_record"
require_relative "conversion_rate"
class BananaSplit::Alternative < ActiveRecord::Base
  include BananaSplit::ConversionRate

  belongs_to :experiment, :class_name => "BananaSplit::Experiment"
  attr_accessible :content, :weight, :lookup
  serialize :content

  def self.calculate_lookup(test_name, alternative_name)
    Digest::MD5.hexdigest(BananaSplit.salt + test_name + alternative_name.to_s)
  end

  def self.score_conversion(test_name, viewed_alternative)
    self.update_all("conversions = conversions + 1", :lookup => self.calculate_lookup(test_name, viewed_alternative))
  end

  def self.score_participation(test_name, viewed_alternative)
    self.update_all("participants = participants + 1", :lookup => self.calculate_lookup(test_name, viewed_alternative))
  end

end
