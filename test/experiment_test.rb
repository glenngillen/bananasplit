require_relative "helper"
require_relative "../lib/bananasplit/experiment"
class ExperimentTest < Minitest::Unit::TestCase
  def setup
    @experiment = BananaSplit::Experiment.new(
      name: "My test experiment"
    )
    assert @experiment.valid?
  end

  def test_has_a_name
    @experiment.name = nil
    refute @experiment.valid?
  end

  def test_has_a_minimum_relative_effect_required
    @experiment.min_relative_effect = nil
    refute @experiment.valid?
  end

  def test_has_alternatives
  #  @experiment.alternatives = nil
  #  refute @experiment.valid?
  end

  def test_calculates_requied_sample_size
    # http://www.evanmiller.org/how-not-to-run-an-ab-test.html
  end

  def test_restarts_if_variants_change
  end

  def test_restarts_if_minimum_effect_changes
  end

  def test_picks_same_variant_for_participant
  end

  def test_calculates_completion_rate
  end

  def test_calculates_significance_once_complete
  end

end
