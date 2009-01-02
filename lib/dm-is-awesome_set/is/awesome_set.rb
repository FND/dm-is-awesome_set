module DataMapper
  module Is
    ##
    # Thanks for looking into dm-is-awesome_set.  What makes it so awesome?  Well,
    # the fact that it actually works.  At least I think it does.  Give it a whirl,
    # and if you come across any bugs let me know (check the readme file for
    # information).  Most of what you will be concerned with is the move method,
    # though there are some other helper methods for selecting nodes.
    # The way you use it in your model is like so:
    #
    # def ModelName
    #   include DataMapper::Resource
    #   # ... set up your properties ...
    #  is :awesome_set, :scope => [:col1, :col2], :child_key => [:parent_id]
    # end
    #
    # Note that scope is optional, and :child_key's default is [:parent_id]

    module AwesomeSet
      # Available options for is awesome_set:
      #   :scope => array of keys for scope (default is [])
      #   :child_key => array of keys for setting the parent-child relationship (default is [:parent_id])

      def is_awesome_set(options={})
        extend  DataMapper::Is::AwesomeSet::ClassMethods
        include DataMapper::Is::AwesomeSet::InstanceMethods

        opts = set_options(options)
        [:child_key, :scope].each {|var| raise "#{var} must be an Array" unless opts[var].is_a?(Array)}

        property :lft, Integer, :writer => :private, :index => true
        property :rgt, Integer, :writer => :private, :index => true

        class_opts = {:class_name => self.name, :child_key => opts[:child_key], :order => [:lft.asc], :writer => :protected}
        belongs_to :parent,  class_opts
        has n,     :children, class_opts

        before :save do
          move_without_saving(:root) if lft.nil? #You don't want to use new_record? here.  Trust me, you don't.
        end

      end # def is_awesome_set

      module ClassMethods
        def set_options(options) #:nodoc:
          @ias_options = { :child_key => [:parent_id], :scope => [] }.merge(options)
        end

        def ias_options;  @ias_options || superclass.ias_options end #:nodoc:

        def child_keys; ias_options[:child_key]; end
        def scope_keys; ias_options[:scope]; end
        def is_nested_set? #:nodoc:
          true
        end
        
        # Checks to see if the hash or object contains a valid scope by checking attributes or keys
        def valid_scope?(hash)
          return true if hash.is_a?(self)
          return false unless hash.is_a?(Hash)
          scope_keys.each { |sk| return false unless hash.keys.include?(sk) }
          true
        end

        # Raises an error if the scope is not valid
        def check_scope(hash)
          raise 'Invalid scope: ' + hash.inspect if !valid_scope?(hash)
        end

        # Return only the attributes that deal with the scope, will raise an error on invalid scope
        def extract_scope(hash)
          check_scope(hash)
          ret = {}
          send_to_obj = hash.is_a?(self)
          scope_keys.each { |sk| ret[sk] = send_to_obj ? hash.attribute_get(sk) : hash[sk] }
          ret
        end

        def adjust_gap!(scoped_set, at, adjustment) #:nodoc:
          scoped_set.all(:rgt.gt => at).adjust!({:rgt => adjustment},true)
          scoped_set.all(:lft.gt => at).adjust!({:lft => adjustment},true)
        end

        # Return a hash that gets the roots
        def root_hash
          ret = {}
          child_keys.each { |ck| ret[ck] = nil }
          ret
        end


        # Get the root with no args if there is no scope
        # Pass the scope or an object with scope to get the first root
        def root(scope = {})
          scope = extract_scope(scope)
          get_class.first(scope.merge(root_hash.merge(:order => [:lft.asc])))
        end

        # Same as @root, but gets all roots
        def roots(scope = {})
          scope = extract_scope(scope)
          get_class.all(scope.merge(root_hash.merge(:order => [:lft.asc])))
        end

        # Gets the full set with scope behavior like @root
        def full_set(scope = {})
          scope = extract_scope(scope)
          get_class.all(scope.merge(:order => [:lft.asc]))
        end

        # Retrieves all nodes that do not have children.
        # This needs to be refactored for more of a DM style, if possible.
        def leaves(scope = {})
          scope = extract_scope(scope)
          get_class.all(scope.merge(:order => [:lft.asc], :conditions => ["`rgt` - `lft` = 1"]))
        end
        
        # Since DataMapper looks for all records in a table when using discriminators
        # when using the parent model , we'll look for the earliest ancestor class
        # that is a nested set.
        def get_class #:nodoc:
          klass = self
          klass = klass.superclass while klass.superclass.respond_to?(:is_nested_set?) && klass.superclass.is_nested_set?
          klass
        end
      end # mod ClassMethods

      module InstanceMethods
        ##
        # move self / node to a position in the set. position can _only_ be changed through this
        #
        # @example [Usage]
        #   * node.move :higher           # moves node higher unless it is at the top of parent
        #   * node.move :lower            # moves node lower unless it is at the bottom of parent
        #   * node.move :below => other   # moves this node below other resource in the set
        #   * node.move :into => other    # same as setting a parent-relationship
        #
        # @param vector <Symbol, Hash> A symbol, or a key-value pair that describes the requested movement
        #
        # @option :higher<Symbol> move node higher
        # @option :highest<Symbol> move node to the top of the list (within its parent)
        # @option :lower<Symbol> move node lower
        # @option :lowest<Symbol> move node to the bottom of the list (within its parent)
        # @option :indent<Symbol> move node into sibling above
        # @option :outdent<Symbol> move node out below its current parent
        # @option :root<Symbol|Hash|Resource> move node to root.  If passed an object / hash, it uses the scope of that.  Otherwise, it uses currently set scope.
        # @option :into<Resource> move node into another node
        # @option :above<Resource> move node above other node
        # @option :below<Resource> move node below other node
        # @option :to<Integer> move node to a specific location in the nested set
        # @see move_without_saving

        def move(vector)
          transaction do
            move_without_saving(vector)
            save!
          end
          reload
        end

        def level
          ancestors.length
        end

        # Gets the root of this node
        def root
          get_class.first(root_hash.merge(:lft.lt => lft, :rgt.gt => rgt))
        end

        # Gets all the roots of this node's tree
        def roots
          get_class.all(root_hash.merge(:order => [:lft.asc]))
        end

        # Gets all ancestors of this node
        def ancestors
          get_class.all(scope_hash.merge(:lft.lt => lft, :rgt.gt => rgt, :order => [:lft.asc]))
        end

        # Same as ancestors, but also including this node
        def self_and_ancestors
          get_class.all(scope_hash.merge(:lft.lte => lft, :rgt.gte => rgt, :order => [:lft.asc]))
        end

        # Gets all nodes that share the same parent node, except for this node
        def siblings
          get_class.all(scope_and_parent_hash.merge(:order => [:lft.asc], :lft.not => lft))
        end

        # Same as siblings, but returns this node as well
        def self_and_siblings
          get_class.all(scope_and_parent_hash.merge(:order => [:lft.asc]))
        end

        # Returns next node with same parent, or nil
        def next_sibling
          get_class.first(scope_and_parent_hash.merge(:lft.gt => rgt, :order => [:lft.asc]))
        end

        # Returns previous node with same parent, or nil
        def previous_sibling
          get_class.first(scope_and_parent_hash.merge(:rgt.lt => lft, :order => [:rgt.desc]))
        end

        # Returns the full set within this scope
        def full_set
          get_class.all(scope_hash)
        end

        # Gets all descendents of this node
        def descendents
          get_class.all(scope_hash.merge(:lft.lt => rgt, :lft.gt => lft, :order => [:lft.asc]))
        end

        # Same as descendents, but returns self as well
        def self_and_descendents
          get_class.all(scope_hash.merge(:rgt.lte => rgt, :lft.gte => lft, :order => [:lft.asc]))
        end

        # Retrieves the nodes without any children.
        def leaves
          get_class.leaves(self)
        end

        def attributes_set(hash) #:nodoc:
          hash = hash || {}
          hash.each { |k,v| attribute_set(k,v) }
        end

        def update!(hash) #:nodoc#
          attributes_set(hash)
          save!
        end

        # Destroys the current node and all children nodes, running their before and after hooks
        # Returns the destroyed objects
        def destroy
          sads = self_and_descendents
          hooks = get_class.const_get('INSTANCE_HOOKS')
          before_methods = hooks[:destroy][:before].map { |hash| hash[:name] }
          after_methods =  hooks[:destroy][:after].map  { |hash| hash[:name] }
          # Trigger all the before :destroy methods
          sads.each { |sad| before_methods.each { |bf| sad.send(bf) } }
          # dup is called here because destroy! likes to clear out the array, understandably.
          transaction do
            sads.dup.destroy!
            adjust_gap!(full_set, lft, -(rgt - lft + 1))
          end
          # Now go through after all the after :destroy methods.
          sads.each { |sad| after_methods.each { |bf| sad.send(bf) } }
        end

        # Same as @destroy, but does not run the hooks
        def destroy!
          sad = self_and_descendents
          transaction do
            sad.dup.destroy!
            adjust_gap!(full_set, lft, -(rgt - lft + 1))
          end
          sad
        end

      protected
        def skip_adjust=(var) #:nodoc:
          @skip_adjust = true
        end

        def adjust_gap!(*args) #:nodoc:
          get_class.adjust_gap!(*args)
        end

        def get_finder_hash(*args)
          ret = {}
          args.each { |arg| get_class.ias_options[arg].each { |s| ret[s] = send(s) } }
          ret
        end

        def root_hash
          ret = {}
          get_class.child_keys.each { |ck| ret[ck] = nil }
          scope_hash.merge(ret)
        end

        def scope_and_parent_hash
          get_finder_hash(:child_key, :scope)
        end

        def extract_scope(hash)
          get_class.extract_scope(hash)
        end

        def scope_hash
          get_finder_hash(:scope)
        end

        def parent_hash
          get_finder_hash(:child_key)
        end

        def same_scope?(obj)
          case obj
          when get_class  :  scope_hash == obj.send(:scope_hash)
          when Hash   :   scope_hash == obj
          when nil    :   true
          end
        end

        def valid_scope?(hash)
          get_class.valid_scope?(hash)
        end

        def move_without_saving(vector)
          # Do some checking of the variable...
          if vector.respond_to?(:'[]') && vector.respond_to?(:size) && vector.size == 1
            action = vector.keys[0]
            obj = vector[action]
          elsif vector.is_a?(Symbol)
            obj = nil
            action = vector
          else
            raise 'You must pass either a symbol or a hash with one property to the method "move".'
          end


          # Convenience methods
          ret_value = case action
          when :higher :  previous_sibling ? move_without_saving(:above => previous_sibling) : false
          when :highest : move_without_saving(:to => parent ? (parent.lft + 1) : 1)
          when :lower : next_sibling ? move_without_saving(:below => next_sibling) : false
          when :lowest : parent ? move_without_saving(:to => parent.rgt - 1) : move_without_saving(:root)
          when :indent : previous_sibling ? move_without_saving(:into => previous_sibling) : false
          when :outdent : parent ? move_without_saving(:below => parent) : false
          else :no_action
          end
          return ret_value unless ret_value == :no_action

          this_gap = lft.to_i > 0 && rgt.to_i > 0 ? rgt - lft : 1
          old_parent = parent
          new_scope = nil
          max = nil

          # Here's where the real heavy lifting happens. Any action can be taken
          # care of by :root, :above, :below, or :to
          pos, adjust_at, p_obj = case action
          when :root
            new_scope = obj ? extract_scope(obj) : scope_hash
            max = (get_class.max(:rgt, new_scope) || 0) + 1
          when :into    :  [obj.rgt, obj.rgt - 1, obj]
          when :above   :  [obj.lft, obj.lft - 1, obj.parent]
          when :below   :  [obj.rgt + 1, obj.rgt, obj.parent]
          when :to
            pos = obj.to_i
            p_obj = get_class.first(scope_hash.merge(:lft.lt => pos, :rgt.gt => pos, :order => [:lft.desc]))
            [pos, pos - 1, p_obj]
          else raise 'Invalid action sent to the method "move": ' + action.to_s
          end

          old_scope = nil
          new_scope ||= extract_scope(p_obj) if p_obj

          max ||= (get_class.max(:rgt, new_scope || scope_hash) || 0) + 1
          if pos == 0 || pos > max
            raise "You cannot move a node outside of the bounds of the tree.  You passed: #{pos}. Acceptable numbers are 1 through #{max}"
          end

          raise 'You are trying to move a node into one that has not been saved yet.' if p_obj && p_obj.lft.nil?

          if lft
            adjustment = pos < lft ? this_gap + 1 : 0
            raise 'Illegal move: you are trying to move a node within itself' if pos.between?(lft+adjustment,rgt+adjustment) && same_scope?(new_scope)
          end

          # make a new hole and assign parent
          adjust_gap!(get_class.full_set(new_scope || scope_hash) , adjust_at, this_gap + 1) if adjust_at
          self.parent = p_obj

          # Do we need to move the node (already present in the tree), or just save the attributes?
          if lft && (pos != lft || !same_scope?(new_scope))
            # Move elements
            if same_scope?(new_scope)
              move_by = pos - (lft + adjustment)
              full_set.all(:lft.gte => lft + adjustment, :rgt.lte => rgt + adjustment).adjust!(:lft => move_by, :rgt => move_by)
            else # Things have to be done a little differently if moving scope
              old_lft = lft
              move_by = pos - lft
              old_scope = extract_scope(self)
              sads = self_and_descendents
              sads.adjust!(:lft => move_by, :rgt => move_by)
              # Update the attributes to match how they are in the database now.
              # Be sure to do this between adjust! and setting the new scope
              attribute_set(:rgt, rgt + move_by)
              attribute_set(:lft, lft + move_by)
              sads.each { |sad| sad.update!(new_scope) }
            end

            # Close hole
            if old_scope
              adjust_gap!(get_class.full_set(old_scope), old_lft, -(this_gap + 1))
            else
              adjustment += 1 if parent == old_parent
              adjust_gap!(full_set, lft + adjustment, -(this_gap + 1))
            end
          else # just save the attributes
            attribute_set(:lft, pos)
            attribute_set(:rgt, lft + this_gap)
            attributes_set(p_obj.send(:scope_hash)) if p_obj
          end

        end
        
        def get_class #:no_doc:
          self.class.get_class
        end
      end # mod InstanceMethods

      Model.send(:include, self)
    end # mod AwesomeSet
  end # mod Is
end # mod DM