module Vanity

  if defined?(::ActiveSupport::SecureRandom)
    SecureRandom = ::ActiveSupport::SecureRandom
  end

  # Helper methods for use in your controllers.
  #
  # 1) Use Vanity from within your controller:
  #
  #   class ApplicationController < ActionController::Base
  #     use_vanity :current_user end
  #   end
  #
  # 2) Present different options for an A/B test:
  #
  #   Get started for only $<%= ab_test :pricing %> a month!
  #
  # 3) Measure conversion:
  #
  #   def signup
  #     track! :pricing
  #     . . .
  #   end
  module Merb
    module UseVanity
    protected

      # Defines the vanity_identity method and the set_identity_context filter.
      #
      # Call with the name of a method that returns an object whose identity
      # will be used as the Vanity identity.  Confusing?  Let's try by example:
      #
      #   class Application < Merb::Controller
      #     use_vanity :current_user
      #
      #     def current_user
      #       User.find(session[:user_id])
      #     end
      #   end
      #
      # If that method (current_user in this example) returns nil, Vanity will
      # set the identity for you (using a cookie to remember it across
      # requests).  It also uses this mechanism if you don't provide an
      # identity object, by calling use_vanity with no arguments.
      #
      # Of course you can also use a block:
      #   class ProjectController < ApplicationController
      #     use_vanity { |controller| controller.params[:project_id] }
      #   end
      def use_vanity(symbol = nil, &block)
        if block
          define_method(:vanity_identity) { block.call(self) }
        else
          define_method :vanity_identity do
            return @vanity_identity if @vanity_identity
            if symbol && object = send(symbol)
              @vanity_identity = object.id
            else
              @vanity_identity = cookies[:vanity_id] || SecureRandom.hex(16)
              cookies.set_cookie(:vanity_id, @vanity_identity, :expires => 1.month.from_now)
              @vanity_identity
            end
          end
        end
        before :set_vanity_context_filter
        after  :reset_vanity_context_filter
        before :vanity_reload_filter if ::Merb.config[:reload_classes]
        before :vanity_query_parameter_filter
      end
    end

    module Filters
    protected

      def set_vanity_context_filter
        @previous_vanity_context, Vanity.context = Vanity.context, self
      end

      def reset_vanity_context_filter
        if context = @previous_vanity_context
          Vanity.context = context
        end
      end

      # This filter allows user to choose alternative in experiment using query
      # parameter.
      #
      # Each alternative has a unique fingerprint (run vanity list command to
      # see them all).  A request with the _vanity query parameter is
      # intercepted, the alternative is chosen, and the user redirected to the
      # same request URL sans _vanity parameter.  This only works for GET
      # requests.
      #
      # For example, if the user requests the page
      # http://example.com/?_vanity=2907dac4de, the first alternative of the
      # :null_abc experiment is chosen and the user redirected to
      # http://example.com/.
      def vanity_query_parameter_filter
        if request.get? && params[:_vanity]
          hashes = Array(params[:_vanity])
          Vanity.playground.experiments.each do |id, experiment|
            if experiment.respond_to?(:alternatives)
              experiment.alternatives.each do |alt|
                if hash = hashes.delete(experiment.fingerprint(alt))
                  experiment.chooses alt.value
                  break
                end
              end
            end
            break if hashes.empty?
          end
          # NOTE: there must be a simpler way to redirect to the exact
          # current url without the _vanity parameter.
          query_params = ::Merb::Parse.query(request.query_string)
          query_params.delete(:_vanity)
          query_string = ::Merb::Parse.params_to_query_string(query_params)
          if query_string.empty?
            redirect request.uri
          else
            redirect "#{request.uri}?#{query_string}"
          end
        end
      end

      # Before filter to reload Vanity experiments/metrics.  Enabled when
      # cache_classes is false (typically, testing environment).
      def vanity_reload_filter
        Vanity.playground.reload!
      end

    end

    module Helpers

    # This method returns one of the alternative values in the named A/B test.
    #
    # @example A/B two alternatives for a page
    #   def index
    #     if ab_test(:new_page) # true/false test
    #       render action: "new_page"
    #     else
    #       render action: "index"
    #     end
    #   end
    # @example Similar, alternative value is page name
    #   def index
    #     render action: ab_test(:new_page)
    #   end
    # @example A/B test inside ERB template (condition)
    #   <%= if ab_test(:banner) %>100% less complexity!<% end %>
    # @example A/B test inside ERB template (value)
    #   <%= ab_test(:greeting) %> <%= current_user.name %>
    # @example A/B test inside ERB template (capture)
    #   <% ab_test :features do |count| %>
    #     <%= count %> features to choose from!
    #   <% end %>
    def ab_test(name, &block)
      value = Vanity.playground.experiment(name).choose
      if block
        content = capture(value, &block)
        block_called_from_erb?(block) ? concat(content) : content
      else
        value
      end
    end

    end

    # Step 1: Add matches to config/router.rb:
    #   to(:controller => "vanities") do
    #     match('/vanity').to(:action => "index").name(:vanity)
    #     match('/vanity/choose/:experiment_id/:alt_id').to(:action => "chooses").name(:vanity_choose_experiment)
    #   end
    #
    # Step 2: Create a new experiments controller:
    #   class Vanities < Application
    #     include Vanity::Merb::Dashboard
    #   end
    #
    # Step 3: Open your browser to http://localhost:3000/vanity
    module Dashboard
      def self.included(base)
        base.show_action(:index, :chooses)
      end
      def index
        Vanity::Commands.render(Vanity.template("report"))
      end
      def chooses(experiment_id, alt_id)
        exp = Vanity.playground.experiment(experiment_id.to_sym)
        exp.chooses(exp.alternatives[alt_id.to_i].value)
        Vanity::Commands.render(Vanity.template("experiment"), :experiment => exp)
      end
    end

  end
end

# Tell Vanity how to generate urls in reports.
if defined?(Merb::Router)
  module Vanity::Render
    def url_for(options)
      ::Merb::Router.url(:vanity_choose_experiment, :experiment_id => options[:e], :alt_id => options[:a])
    end
  end
end

# Enhance Merb::Controller with use_vanity, filters and helper methods.
if defined?(Merb::Controller)
  # Include in controller, add view helper methods.
  Merb::Controller.class_eval do
    extend  Vanity::Merb::UseVanity
    include Vanity::Merb::Filters
    include Vanity::Merb::Helpers
  end
end

if defined?(Merb::BootLoader)
  Merb::BootLoader.after_app_loads do
    Vanity.playground.logger ||= Merb.logger
    Vanity.playground.load_path = Vanity.playground.load_path.match(/^\//) ? Vanity.playground.load_path : Merb.root / Vanity.playground.load_path
    Vanity.playground.load!
    config_file = Merb.root / "config/redis.yml"
    if !Vanity.playground.connected? && File.exist?(config_file)
      config = YAML.load_file(config_file)[Merb.env.to_s]
      Vanity.playground.redis = config if config
    end
  end
end