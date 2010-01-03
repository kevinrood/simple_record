module SimpleRecord
    module Attributes
# For all things related to defining attributes.


        def self.included(base)
            #puts 'Callbacks included in ' + base.inspect
=begin
            instance_eval <<-endofeval

         def self.defined_attributes
                #puts 'class defined_attributes'
                @attributes ||= {}
                @attributes
            endendofeval
            endofeval
=end

        end

        def defined_attributes
            @attributes ||= {}
            @attributes
        end

        def has_attributes(*args)
            args.each do |arg|
                arg_options = nil
                if arg.is_a?(Hash)
                    # then attribute may have extra options
                    arg_options = arg
                    arg = arg_options[:name]
                end
                attr = Attribute.new(:string, arg_options)
                defined_attributes[arg] = attr if defined_attributes[arg].nil?

                # define reader method
                arg_s = arg.to_s # to get rid of all the to_s calls
                send(:define_method, arg) do
                    ret = get_attribute(arg)
                    return ret
                end

                # define writer method
                send(:define_method, arg_s+"=") do |value|
                    set(arg, value)
                end

                # Now for dirty methods: http://api.rubyonrails.org/classes/ActiveRecord/Dirty.html
                # define changed? method
                send(:define_method, arg_s + "_changed?") do
                    @dirty.has_key?(arg_s)
                end

                # define change method
                send(:define_method, arg_s + "_change") do
                    old_val = @dirty[arg_s]
                    [old_val, get_attribute(arg_s)]
                end

                # define was method
                send(:define_method, arg_s + "_was") do
                    old_val = @dirty[arg_s]
                    old_val
                end
            end
        end

        def has_strings(*args)
            has_attributes(*args)
        end

        def has_ints(*args)
            has_attributes(*args)
            are_ints(*args)
        end

        def has_dates(*args)
            has_attributes(*args)
            are_dates(*args)
        end

        def has_booleans(*args)
            has_attributes(*args)
            are_booleans(*args)
        end

        def are_ints(*args)
            #    puts 'calling are_ints: ' + args.inspect
            args.each do |arg|
                defined_attributes[arg].type = :int
            end
        end

        def are_dates(*args)
            args.each do |arg|
                defined_attributes[arg].type = :date
            end
        end

        def are_booleans(*args)
            args.each do |arg|
                defined_attributes[arg].type = :boolean
            end
        end

        @@virtuals=[]

        def has_virtuals(*args)
            @@virtuals = args
            args.each do |arg|
                #we just create the accessor functions here, the actual instance variable is created during initialize
                attr_accessor(arg)
            end
        end

        # One belongs_to association per call. Call multiple times if there are more than one.
        #
        # This method will also create an {association)_id method that will return the ID of the foreign object
        # without actually materializing it.
        def belongs_to(association_id, options = {})
            arg = association_id
            arg_s = arg.to_s
            arg_id = arg.to_s + '_id'
            attribute = Attribute.new(:belongs_to, options)
            defined_attributes[arg] = attribute

            # todo: should also handle foreign_key http://74.125.95.132/search?q=cache:KqLkxuXiBBQJ:wiki.rubyonrails.org/rails/show/belongs_to+rails+belongs_to&hl=en&ct=clnk&cd=1&gl=us
            #    puts "arg_id=#{arg}_id"
            #        puts "is defined? " + eval("(defined? #{arg}_id)").to_s
            #        puts 'atts=' + @attributes.inspect

            # Define reader method
            send(:define_method, arg) do
#                puts 'GETTING ' + arg.to_s
                attribute = defined_attributes_local[arg]
                options2 = attribute.options # @@belongs_to_map[arg]
                class_name = options2[:class_name] || arg.to_s[0...1].capitalize + arg.to_s[1...arg.to_s.length]

                # Camelize classnames with underscores (ie my_model.rb --> MyModel)
                class_name = class_name.camelize

                #      puts "attr=" + @attributes[arg_id].inspect
                #      puts 'val=' + @attributes[arg_id][0].inspect unless @attributes[arg_id].nil?
                ret = nil
                arg_id = arg.to_s + '_id'
                arg_id_val = send("#{arg_id}")
                if arg_id_val
                    if !cache_store.nil?
#                        arg_id_val = @attributes[arg_id][0]
                        cache_key = self.class.cache_key(class_name, arg_id_val)
#          puts 'cache_key=' + cache_key
                        ret = cache_store.read(cache_key)
#          puts 'belongs_to incache=' + ret.inspect
                    end
                    if ret.nil?
                        to_eval = "#{class_name}.find('#{arg_id_val}')"
#      puts 'to eval=' + to_eval
                        begin
                            ret = eval(to_eval) # (defined? #{arg}_id)
                        rescue Aws::ActiveSdb::ActiveSdbError
                            if $!.message.include? "Couldn't find"
                                ret = nil
                            else
                                raise $!
                            end
                        end

                    end
                end
#      puts 'ret=' + ret.inspect
                return ret
            end


            # Define writer method
            send(:define_method, arg.to_s + "=") do |value|
                set(arg, value)
            end


            # Define ID reader method for reading the associated objects id without getting the entire object
            send(:define_method, arg_id) do
                val1 = @attributes[arg_id]
                if val1
                    if val1.is_a?(Array)
                        if val1.size > 0 && val1[0].present?
                            return val1[0]
                        end

                    else
                        return val1
                    end
                end
                return nil
            end

            # Define writer method for setting the _id directly without the associated object
            send(:define_method, arg_id + "=") do |value|
                if value.nil?
                    self[arg_id] = nil unless self[arg_id].nil? # if it went from something to nil, then we have to remember and remove attribute on save
                else
                    self[arg_id] = value
                end
            end

            send(:define_method, "create_"+arg.to_s) do |*params|
                newsubrecord=eval(arg.to_s.classify).new(*params)
                newsubrecord.save
                arg_id = arg.to_s + '_id'
                self[arg_id]=newsubrecord.id
            end
        end

        def has_many(*args)
            args.each do |arg|
                #okay, this creates an instance method with the pluralized name of the symbol passed to belongs_to
                send(:define_method, arg) do
                    #when called, the method creates a new, very temporary instance of the Activerecordtosdb_subrecord class
                    #It is passed the three initializers it needs:
                    #note the first parameter is just a string by time new gets it, like "user"
                    #the second and third parameters are still a variable when new gets it, like user_id
                    return eval(%{Activerecordtosdb_subrecord_array.new('#{arg}', self.class.name ,id)})
                end
            end
            #Disclaimer: this whole funciton just seems crazy to me, and a bit inefficient. But it was the clearest way I could think to do it code wise.
            #It's bad programming form (imo) to have a class method require something that isn't passed to it through it's variables.
            #I couldn't pass the id when calling find, since the original find doesn't work that way, so I was left with this.
        end

        def has_one(*args)

        end


        def self.handle_virtuals(attrs)
            @@virtuals.each do |virtual|
                #we first copy the information for the virtual to an instance variable of the same name
                eval("@#{virtual}=attrs['#{virtual}']")
                #and then remove the parameter before it is passed to initialize, so that it is NOT sent to SimpleDB
                eval("attrs.delete('#{virtual}')")
            end
        end

        # Holds information about an attribute
        class Attribute
            attr_accessor :type, :options

            def initialize(type, options=nil)
                @type = type
                @options = options
            end

        end

    end
end