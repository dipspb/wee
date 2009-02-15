module Wee

  #
  # The base class of all components. You should at least overwrite method
  # #render in your own subclasses.
  #
  class Component < Presenter

    # Process and invoke all callbacks specified for this component and all of
    # it's child components. 

    def process_callbacks(callbacks)
      callbacks.input_callbacks.each_triggered(self) do |callback, value|
        callback.call(value)
      end

      # process callbacks of all children
      each_child do |child|
        child.decoration.process_callbacks(callbacks)
      end

      callbacks.action_callbacks.each_triggered(self) do |callback, value|
        callback.call
        # TODO: return to main loop
      end
    end

    protected

    # Initializes a newly created component.
    #
    # Call this method from your own components' <i>initialize</i> method using
    # +super+, before setting up anything else! 

    def initialize() # :notnew:
      @decoration = self
      @children = nil
    end

    protected

    #
    # Iterates over all direct child components. 
    #
    def each_child(&block)
      @children.each(&block) if @children
    end

    # Add a child to the component. Example:
    # 
    #   class YourComponent < Wee::Component
    #     def initialize
    #       super()
    #       add_child ChildComponent.new
    #     end
    #   end
    #
    # If you dynamically add child components to a component at run-time (not in
    # initialize), then you should consider to backtrack the children array (of
    # course only if you want backtracking at all): 
    #   
    #   def backtrack_state(snapshot)
    #     super
    #     snapshot.add(self.children)
    #   end
    #

    def add_child(child)
      (@children ||= []) << child
      child
    end

    include Wee::DecorationMixin

    public

    # Take snapshots of objects that should correctly be backtracked.
    #
    # Backtracking means that you can go back in time of the components' state.
    # Therefore it is neccessary to take snapshots of those objects that want to
    # participate in backtracking. Taking snapshots of the whole component tree
    # would be too expensive and unflexible. Note that methods
    # <i>take_snapshot</i> and <i>restore_snapshot</i> are called for those
    # objects to take the snapshot (they behave like <i>marshal_dump</i> and
    # <i>marshal_load</i>). Overwrite them if you want to define special
    # behaviour. 
    #
    # For example if you dynamically add children to your component, you might
    # want to backtrack the children array: 
    #
    #   def backtrack_state(state)
    #     super
    #     backtrack_children(state)
    #   end
    #
    # Or, those components that dynamically add decorations or make use of the 
    # call/answer mechanism should backtrack decorations as well: 
    #
    #   def backtrack_state(state)
    #     super
    #     backtrack_children(state)
    #     backtrack_decoration(state)
    #   end
    #
    # [+state+]
    #    An object of class State

    def backtrack_state(state)
      each_child do |child|
        child.decoration.backtrack_state(state)
      end
    end

    def backtrack_decoration(state)
      state.add_ivar(self, :@decoration, @decoration)
    end

    def backtrack_children(state)
      state.add_ivar(self, :@children, (@children and @children.dup))
    end

    protected

    # Call another component. The calling component is neither rendered nor are
    # it's callbacks processed until the called component answers using method
    # #answer. 
    #
    # [+component+]
    #   The component to be called.
    #
    # [+return_callback+]
    #   Is invoked when the called component answers.
    #   Either a symbol or any object that responds to #call. If it's a symbol,
    #   then the corresponding method of the current component will be called.
    #
    # [+args+]
    #   Arguments that are passed to the +return_callback+ before the 'onanswer'
    #   arguments.
    #
    # <b>How it works</b>
    # 
    # The component to be called is wrapped with an AnswerDecoration and the
    # +return_callback+ parameter is assigned to it's +on_answer+ attribute (not
    # directly as there are cleanup actions to be taken before the
    # +return_callback+ can be invoked, hence we wrap it in the OnAnswer class).
    # Then a Delegate decoration is added to the calling component (self), which
    # delegates to the component to be called (+component+). 
    #
    # Then we unwind the calling stack back to the Session by throwing
    # <i>:wee_abort_callback_processing</i>. This means, that there is only ever
    # one action callback invoked per request. This is not neccessary, we could
    # simply omit this, but then we'd break compatibility with the implementation
    # using continuations.
    #
    # When at a later point in time the called component invokes #answer, this
    # will throw a <i>:wee_answer</i> exception which is catched in the
    # AnswerDecoration. The AnswerDecoration then invokes the +on_answer+
    # callback which cleans up the decorations we added during #call, and finally
    # passes control to the +return_callback+. 
    #

    def call(component, return_callback=nil, *args)
      add_decoration(delegate = Wee::Delegate.new(component))
      component.add_decoration(answer = Wee::AnswerDecoration.new)
      answer.on_answer = OnAnswer.new(self, component, delegate, answer, 
                                      return_callback, args)
      send_response(nil)
    end

    class OnAnswer < Struct.new(:calling_component, :called_component, :delegate, 
                                :answer, :return_callback, :args)

      def call(*answer_args)
        calling_component.remove_decoration(delegate)
        called_component.remove_decoration(answer)
        return if return_callback.nil?
        if return_callback.respond_to?(:call)
          return_callback.call(*(args + answer_args))
        else
          calling_component.send(return_callback, *(args + answer_args))
        end
      end
    end

    # Return from a called component.
    # 
    # NOTE that #answer never returns.
    #
    # See #call for a detailed description of the call/answer mechanism.

    def answer(*args)
      throw :wee_answer, args 
    end

  end # class Component

end # module Wee
