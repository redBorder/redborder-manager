# frozen_string_literal: true

require 'test/unit'
require 'json'
require 'net/http'
require_relative '../../resources/scripts/rb_druid_rules'

# Initializes the test environment with default values for the `@opt`, `@node`, and `@datasource` instance variables.
class RbDruidRulesTest < Test::Unit::TestCase
  def setup
    @opt = {}
    @node = 'localhost'
    @datasource = 'test_datasource'
  end

  def test_hot_and_default_forever
    @opt = { 'r' => '2', 'i' => '1', 'p' => 'P1D', 'd' => 'P10000D' }

    expected_payload = [
      { type: :loadByPeriod, period: 'P1D',
        tieredReplicants: { hot: 2, '_default_tier' => 0 } },
      { type: :loadForever,
        tieredReplicants: { hot: 0, '_default_tier' => 1 } }
    ]

    mock_http_request(expected_payload)

    assert_nothing_raised do
      load_druid_rules(@opt, @node, @datasource)
    end
  end

  def test_only_default_period
    @opt = { 'r' => '0', 'i' => '2', 'p' => 'PT0S', 'd' => 'P30D' }

    expected_payload = [
      { type: :loadByPeriod, period: 'P30D',
        tieredReplicants: { '_default_tier' => 2 } },
      { type: :dropForever }
    ]

    mock_http_request(expected_payload)

    assert_nothing_raised do
      load_druid_rules(@opt, @node, @datasource)
    end
  end

  def test_hot_and_default_periods
    @opt = { 'r' => '3', 'i' => '1', 'p' => 'P1D', 'd' => 'P30D' }

    expected_payload = [
      { type: :loadByPeriod, period: 'P1D',
        tieredReplicants: { hot: 3, '_default_tier' => 0 } },
      { type: :loadByPeriod, period: 'P30D',
        tieredReplicants: { hot: 0, '_default_tier' => 1 } },
      { type: :dropForever }
    ]

    mock_http_request(expected_payload)

    assert_nothing_raised do
      load_druid_rules(@opt, @node, @datasource)
    end
  end

  private

  def mock_http_request(expected_payload)
    mock_response = Struct.new(:code).new('200')
    Net::HTTP.stub(:start) do |&block|
      block.call(Struct.new(:request).new(mock_response))
    end

    Net::HTTP::Post.stub(:new) do |_uri|
      post = Object.new
      def post.content_type=(_value); end

      def post.body=(value)
        parsed_body = JSON.parse(value)
        assert_equal @expected_payload, parsed_body
      end
      post.instance_variable_set(:@expected_payload, expected_payload)
      post
    end
  end
end
