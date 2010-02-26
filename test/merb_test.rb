require "test/test_helper"

class Vanities < Merb::Controller
  class User < Struct.new(:id); end

  attr_accessor :current_user

  def index
    ab_test(:pie_or_cake)
  end

  def identity
    vanity_identity.to_s
  end

  def identity_user
    self.current_user = User.new(params[:user_id])
    vanity_identity.to_s
  end
end

class UseVanityInMerbTest < Test::Unit::TestCase
  include Merb::Test::MakeRequest

  def setup
    super
    metric :sugar_high
    new_ab_test :pie_or_cake do
      metrics :sugar_high
    end
    Vanities.class_eval do
      use_vanity :current_user
    end

    @old_routes = Merb::Router.routes
    Merb::Router.prepare(@old_routes) do
      match('/vanity(/:action)').to(:controller => "vanities")
    end
  end

  def test_vanity_cookie_is_persistent
    @response = request("/vanity")
    assert cookie = @response.headers["Set-Cookie"].find { |c| c[/^vanity_id=/] }
    assert expires = cookie[/vanity_id=[a-f0-9]{32}; expires=(.*); path=\/;/, 1]
    assert_in_delta Time.parse(expires), Time.now + 1.month, 1.minute
  end

  def test_vanity_cookie_default_id
    @response = request("/vanity")
    assert cookie = @response.headers["Set-Cookie"].find { |c| c[/^vanity_id=/] }
    assert cookie =~ /^vanity_id=[a-f0-9]{32};/
  end

  def test_vanity_cookie_retains_id
    @response = request("/vanity", :cookie => "vanity_id=from_last_time")
    assert cookie = @response.headers["Set-Cookie"].find { |c| c[/^vanity_id=/] }
    assert cookie =~ /^vanity_id=from_last_time;/
  end

  def test_vanity_identity_set_from_cookie
    @response = request("/vanity/identity", :cookie => ["vanity_id=from_last_time"])
    @response.body.to_s.should == "from_last_time"
  end

  def test_vanity_identity_set_from_user
    @response = request("/vanity/identity_user", :params => { :user_id => 999 })
    @response.body.to_s.should == "999"
  end

  def test_vanity_identity_with_no_user_model
    Vanities.class_eval do
      use_vanity nil
    end
    @response = request("/vanity/identity")
    assert cookie = @response.headers["Set-Cookie"].find { |c| c[/^vanity_id=/] }
    assert cookie =~ /^vanity_id=[a-f0-9]{32};/
  end

  def test_vanity_identity_set_with_block
    Vanities.class_eval do
      def project_id; "576" end
      use_vanity { |controller| controller.project_id }
    end
    @response = request("/vanity/identity")
    @response.body.to_s.should == "576"
  end
#
#   # query parameter filter
#
#   def test_redirects_and_loses_vanity_query_parameter
#     get :index, :foo=>"bar", :_vanity=>"567"
#     assert_redirected_to "/use_vanity?foo=bar"
#   end
#
#   def test_sets_choices_from_vanity_query_parameter
#     first = experiment(:pie_or_cake).alternatives.first
#     # experiment(:pie_or_cake).fingerprint(first)
#     10.times do
#       @controller = nil ; setup_controller_request_and_response
#       get :index, :_vanity=>"aae9ff8081"
#       assert !experiment(:pie_or_cake).choose
#       assert experiment(:pie_or_cake).showing?(first)
#     end
#   end
#
#   def test_does_nothing_with_vanity_query_parameter_for_posts
#     first = experiment(:pie_or_cake).alternatives.first
#     post :index, :foo=>"bar", :_vanity=>"567"
#     assert_response :success
#     assert !experiment(:pie_or_cake).showing?(first)
#   end
#
#
#   # -- Load path --
#
#   def test_load_path
#     assert_equal File.expand_path("tmp/experiments"), load_rails(<<-RB)
# initializer.after_initialize
# $stdout << Vanity.playground.load_path
#     RB
#   end
#
#   def test_settable_load_path
#     assert_equal File.expand_path("tmp/predictions"), load_rails(<<-RB)
# Vanity.playground.load_path = "predictions"
# initializer.after_initialize
# $stdout << Vanity.playground.load_path
#     RB
#   end
#
#   def test_absolute_load_path
#     assert_equal File.expand_path("/tmp/var"), load_rails(<<-RB)
# Vanity.playground.load_path = "/tmp/var"
# initializer.after_initialize
# $stdout << Vanity.playground.load_path
#     RB
#   end
#
#
#   # -- Connection configuration --
#
#   def test_default_connection
#     assert_equal "localhost:6379", load_rails(<<-RB)
# initializer.after_initialize
# $stdout << Vanity.playground.redis.server
#     RB
#   end
#
#   def test_configured_connection
#     assert_equal "127.0.0.1:6379", load_rails(<<-RB)
# Vanity.playground.redis = "127.0.0.1:6379"
# initializer.after_initialize
# $stdout << Vanity.playground.redis.server
#     RB
#   end
#
#   def test_test_connection
#     assert_equal "Vanity::MockRedis", load_rails(<<-RB)
# Vanity.playground.test!
# initializer.after_initialize
# $stdout << Vanity.playground.redis.class
#     RB
#   end
#
#   def test_connection_from_yaml
#     FileUtils.mkpath "tmp/config"
#     yml = File.open("tmp/config/redis.yml", "w")
#     yml << "production: internal.local:6379\n"
#     yml.flush
#     assert_equal "internal.local:6379", load_rails(<<-RB)
# initializer.after_initialize
# $stdout << Vanity.playground.redis.server
#     RB
#   ensure
#     File.unlink yml
#   end
#
#   def test_connection_from_yaml_missing
#     FileUtils.mkpath "tmp/config"
#     yml = File.open("tmp/config/redis.yml", "w")
#     yml << "development: internal.local:6379\n"
#     yml.flush
#     assert_equal "localhost:6379", load_rails(<<-RB)
# initializer.after_initialize
# $stdout << Vanity.playground.redis.server
#     RB
#   ensure
#     File.unlink yml
#   end
#
#
#   def load_rails(code)
#     tmp = Tempfile.open("test.rb")
#     tmp.write <<-RB
# $:.delete_if { |path| path[/gems\\/vanity-\\d/] }
# $:.unshift File.expand_path("../lib")
# RAILS_ROOT = File.expand_path(".")
# RAILS_ENV = "production"
# require "initializer"
# require "active_support"
# Rails.configuration = Rails::Configuration.new
# initializer = Rails::Initializer.new(Rails.configuration)
# initializer.check_gem_dependencies
# require "vanity"
#     RB
#     tmp.write code
#     tmp.flush
#     Dir.chdir "tmp" do
#       open("|ruby #{tmp.path}").read
#     end
#   rescue
#     tmp.close!
#   end


  def teardown
    super
    # UseVanityController.send(:filter_chain).clear
    Merb::Router.prepare(@old_routes) { }
  end

end
