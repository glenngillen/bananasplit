require_relative 'test_helper'

class BananaSplitTest < Test::Unit::TestCase

  setup do
    BananaSplit.options = {}
  end

  teardown do
    BananaSplit.cache.clear
    BananaSplit::Experiment.delete_all
    BananaSplit::Alternative.delete_all
  end

  test "identity automatically assigned" do
    split = BananaSplit.identify
    assert split.identity != nil
  end

  test "alternative parsing" do
    array = %w{a b c}
    assert_equal array, BananaSplit.parse_alternatives(array)
    assert_equal 65, BananaSplit.parse_alternatives(65).size
    assert_equal 4, BananaSplit.parse_alternatives(2..5).size
    assert !(BananaSplit.parse_alternatives(2..5).include? 1)
  end

  test "experiment creation" do
    assert_equal 0, BananaSplit::Experiment.count
    assert_equal 0, BananaSplit::Alternative.count
    alternatives = %w{A B}
    split = BananaSplit.identify
    alternative_selected = split.test("unit_test_sample_A", alternatives)
    assert_equal 1, BananaSplit::Experiment.count
    assert_equal 2, BananaSplit::Alternative.count
    assert alternatives.include?(alternative_selected)
  end

  test "exists works right" do
    split = BananaSplit.identify
    split.test("exist works right", %w{does does_not})
    assert BananaSplit::Experiment.exists?("exist works right")
  end

  test "alternatives picked consistently" do
    split = BananaSplit.identify
    alternative_picked = split.test("consistency_test", 1..100)
    100.times do
      assert_equal alternative_picked, split.test("consistency_test", 1..100)
    end
  end

  test "participation works" do
    new_tests = %w{participationA participationB participationC}
    split = BananaSplit.identify
    new_tests.map do |test_name|
      split.test(test_name, 1..5)
    end

    participating_tests = BananaSplit.cache.read("BananaSplit::participating_tests::#{split.identity}") || []

    new_tests.map do |test_name|
      assert participating_tests.include? test_name
    end
  end

  test "participants counted" do
    test_name = "participants_counted_test"
    split = BananaSplit.identify
    alternative = split.test(test_name, %w{a b c})

    ex = BananaSplit::Experiment.find_by_test_name(test_name)
    lookup = BananaSplit::Alternative.calculate_lookup(test_name, alternative)
    chosen_alt = BananaSplit::Alternative.find_by_lookup(lookup)
    assert_equal 1, ex.participants
    assert_equal 1, chosen_alt.participants
  end

  test "conversion tracking by test name" do
    test_name = "conversion_test_by_name"
    split = BananaSplit.identify
    alternative = split.test(test_name, %w{a b c})
    split.bingo!(test_name)
    ex = BananaSplit::Experiment.find_by_test_name(test_name)
    lookup = BananaSplit::Alternative.calculate_lookup(test_name, alternative)
    chosen_alt = BananaSplit::Alternative.find_by_lookup(lookup)
    assert_equal 1, ex.conversions
    assert_equal 1, chosen_alt.conversions
    split.bingo!(test_name)

    #Should still only have one because this conversion should not be double counted.
    #We haven't specified that in the test options.
    assert_equal 1, BananaSplit::Experiment.find_by_test_name(test_name).conversions
  end

  test "conversion tracking by conversion name" do
    split = BananaSplit.identify
    conversion_name = "purchase"
    tests = %w{conversionTrackingByConversionNameA conversionTrackingByConversionNameB conversionTrackingByConversionNameC}
    tests.map do |test_name|
      split.test(test_name, %w{A B}, :conversion => conversion_name)
    end

    split.bingo!(conversion_name)
    tests.map do |test_name|
      assert_equal 1, BananaSplit::Experiment.find_by_test_name(test_name).conversions
    end
  end

  test "short circuiting works" do
    conversion_name = "purchase"
    test_name = "short circuit test"
    split = BananaSplit.identify
    alt_picked = split.test(test_name, %w{A B}, :conversion => conversion_name)
    ex = BananaSplit::Experiment.find_by_test_name(test_name)
    alt_not_picked = (%w{A B} - [alt_picked]).first

    ex.end_experiment!(alt_not_picked, conversion_name)

    ex.reload
    assert_equal "Finished", ex.status

    split.bingo!(test_name)  #Should not be counted, test is over.
    assert_equal 0, ex.conversions

    new_bingo = BananaSplit.identify("shortCircuitTestNewIdentity")
    new_bingo.test(test_name, %w{A B}, :conversion => conversion_name)
    ex.reload
    assert_equal 1, ex.participants  #Original identity counted, new identity not counted b/c test stopped
  end

  test "proper experiment creation in high concurrency" do
    conversion_name = "purchase"
    test_name = "high_concurrency_test"
    alternatives = %w{foo bar}

    threads = []
    5.times do
      threads << Thread.new do
        split = BananaSplit.identify
        split.test(test_name, alternatives, :conversion => conversion_name)
        ActiveRecord::Base.connection.close
      end
    end
    threads.each(&:join)
    assert_equal 1, BananaSplit::Experiment.count_by_sql(["select count(id) from experiments where test_name = ?", test_name])
  end

  test "proper conversions with concurrency" do
    test_name = "conversion_concurrency_test"
    alternatives = %w{foo bar}
    threads = []
    alternatives.size.times do |i|
      threads << Thread.new do
        split = BananaSplit.identify(i)
        split.test(test_name, alternatives)
        split.bingo!(test_name)
        sleep(0.3) if i == 0
        ActiveRecord::Base.connection.close
      end
    end
    threads.each(&:join)
    ex = BananaSplit::Experiment.find_by_test_name(test_name)
    ex.alternatives.each do |alternative|
      assert_equal 1, alternative.conversions
    end
  end

  test "non-humans are ignored for participation and conversions if not explicitly counted" do
    BananaSplit.options[:count_humans_only] = true
    BananaSplit.options[:expires_in] = 1.hour
    BananaSplit.options[:expires_in_for_bots] = 3.seconds
    first_identity = BananaSplit.identify("unsure_if_human#{Time.now.to_i}")
    test_name = "are_you_a_human"
    first_identity.test(test_name, %w{does_not matter})

    assert !first_identity.is_human?, "Identity not marked as human yet."

    ex = BananaSplit::Experiment.find_by_test_name(test_name)
    first_identity.bingo!(test_name)
    assert_equal 0, ex.participants, "Not human yet, so should have no participants."
    assert_equal 0, ex.conversions, "Not human yet, so should have no conversions."

    first_identity.human!

    #Setting up second participant who doesn't convert.
    second_identity = BananaSplit.identify("unsure_if_human_2_#{Time.now.to_i}")
    second_identity.test(test_name, %w{does_not matter})
    second_identity.human!

    ex = BananaSplit::Experiment.find_by_test_name(test_name)
    assert_equal 2, ex.participants, "Now that we're human, our participation should matter."
    assert_equal 1, ex.conversions, "Now that we're human, our conversions should matter, but only one of us converted."
  end

  test "Participating tests for a given identity" do
    split = BananaSplit.identify("test_participant")
    test_names = (1..3).map {|t| "participating_test_test_name #{t}"}
    test_alternatives = %w{yes no}
    test_names.each {|test_name| split.test(test_name, test_alternatives)}
    ex = BananaSplit::Experiment.last
    ex.end_experiment!("no")  #End final of 3 tests, leaving 2 presently running

    assert_equal 2, split.participating_tests.size  #Pairs for two tests
    split.participating_tests.each do |key, value|
      assert test_names.include? key
      assert test_alternatives.include? value
    end

    assert_equal 3, split.participating_tests(false).size #pairs for three tests
    split.participating_tests(false).each do |key, value|
      assert test_names.include? key
      assert test_alternatives.include? value
    end

    non_participant = BananaSplit.identify("test_nonparticipant")
    assert_equal({}, non_participant.participating_tests)
  end

end
