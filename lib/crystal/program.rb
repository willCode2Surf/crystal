require_relative "types"
require_relative "unification"

module Crystal
  class Program < ModuleType
    include Enumerable

    POINTER_SIZE = 8

    attr_accessor :symbols
    attr_accessor :global_vars

    def initialize
      super('main')

      @generic_types = Hash.new { |h, k| h[k] = {} }
      @unions = {}

      object = @types["Object"] = ObjectType.new "Object", nil, self
      value = @types["Value"] = ObjectType.new "Value", object, self
      numeric = @types["Numeric"] = ObjectType.new "Numeric", value, self

      @types["Void"] = PrimitiveType.new "Void", value, LLVM::Int8, 1, self
      @types["Nil"] = PrimitiveType.new "Nil", value, LLVM::Int1, 1, self
      @types["Bool"] = PrimitiveType.new "Bool", value, LLVM::Int1, 1, self
      @types["Char"] = PrimitiveType.new "Char", value, LLVM::Int8, 1, self
      @types["Short"] = PrimitiveType.new "Short", value, LLVM::Int16, 2, self
      @types["Int"] = PrimitiveType.new "Int", numeric, LLVM::Int32, 4, self
      @types["Long"] = PrimitiveType.new "Long", numeric, LLVM::Int64, 8, self
      @types["Float"] = PrimitiveType.new "Float", numeric, LLVM::Float, 4, self
      @types["Double"] = PrimitiveType.new "Double", numeric, LLVM::Double, 8, self
      @types["Symbol"] = PrimitiveType.new "Symbol", value, LLVM::Int32, 4, self
      @types["Pointer"] = PointerType.new value, self

      @types["String"] = ObjectType.new "String", object, self
      string.lookup_instance_var('@length').type = int
      string.lookup_instance_var('@c').type = char

      array = @types["Array"] = ObjectType.new "Array", object, self
      array.string_rep = proc do |type|
        buffer = type.instance_vars["@buffer"]
        if buffer
          element_type = buffer.type.var.type
          "Array<#{element_type}>"
        else
          nil
        end
      end
      array.generic = true

      @types["ARGC_UNSAFE"] = Const.new "ARGC_UNSAFE", Crystal::ARGC.new(int), self
      @types["ARGV_UNSAFE"] = Const.new "ARGV_UNSAFE", Crystal::ARGV.new(pointer_of(pointer_of(char))), self

      @types["Math"] = ModuleType.new "Math", self

      @symbols = Set.new
      @global_vars = {}

      @requires = Set.new

      @nil_var = Var.new('nil', self.nil)

      define_primitives
    end

    def program
      self
    end

    def type_merge(*types)
      types = types.reject { |type| type.is_a?(ProxyType) && type.dead }
      all_types = types.map! { |type| type.is_a?(UnionType) ? type.types : type }
      all_types.flatten!
      all_types.compact!
      all_types.uniq!(&:type_id)
      all_types.sort_by!(&:type_id)
      if all_types.length == 1
        return all_types[0]
      end

      all_types_ids = all_types.map(&:type_id)
      @unions[all_types_ids] ||= UnionType.new(*all_types)
    end

    def lookup_generic_type(type, instance_vars)
      key = instance_vars.map { |k, v| [k, v.type_id] }.sort_by { |a| a[0] }
      full_name = type.internal_full_name
      type = lookup_type full_name.split('::')
      generic_type = @generic_types[full_name][key]
      unless generic_type
        generic_type = type.clone
        generic_type.instance_vars = instance_vars
        @generic_types[full_name][key] = generic_type
      end
      generic_type
    end


    def unify(node)
      @unify_visitor ||= UnifyVisitor.new
      Crystal.unify node, @unify_visitor
    end

    def nil_var
      @nil_var
    end

    def value
      @types["Value"]
    end

    def nil
      @types["Nil"]
    end

    def object
      @types["Object"]
    end

    def bool
      @types["Bool"]
    end

    def char
      @types["Char"]
    end

    def int
      @types["Int"]
    end

    def long
      @types["Long"]
    end

    def float
      @types["Float"]
    end

    def double
      @types["Double"]
    end

    def string
      @types["String"]
    end

    def symbol
      @types["Symbol"]
    end

    def array
      @types["Array"]
    end

    def pointer
      @types["Pointer"]
    end

    def char_pointer
      pointer_of @types['Char']
    end

    def pointer_of(type)
      p = pointer.clone
      p.var.type = type
      p
    end

    def metaclass
      self
    end

    def passed_as_self?
      false
    end

    def require(filename, relative_to = nil)
      if relative_to && (single = filename =~ /(.+)\/\*\Z/ || multi = filename =~ /(.+)\/\*\*\Z/)
        dir = File.dirname relative_to
        relative_dir = File.join(dir, $1)
        if File.directory?(relative_dir)
          nodes = []
          Dir["#{relative_dir}/#{multi ? '**/' : ''}*.cr"].each do |file|
            node = require_absolute(file)
            nodes.push node if node
          end
          return Expressions.new(nodes)
        end
      end

      filename = "#{filename}.cr" unless filename.end_with? ".cr"
      if relative_to
        dir = File.dirname relative_to
        relative_filename = File.join(dir, filename)
        if File.exists?(relative_filename)
          require_absolute relative_filename
        else
          require_from_load_path filename
        end
      else
        require_from_load_path filename
      end
    end

    def require_absolute(file)
      file = File.absolute_path(file)
      return nil if @requires.include? file

      @requires.add file

      parser = Parser.new File.read(file)
      parser.filename = file
      node = parser.parse
      node.accept TypeVisitor.new(self) if node
      node
    end

    def require_from_load_path(file)
      require_absolute File.expand_path("../../../std/#{file}", __FILE__)
    end

    def library_names
      libs = []
      @types.values.each do |type|
        if type.is_a?(LibType) && type.libname
          libs << type.libname
        end
      end
      libs
    end

    def load_libs
      libs = library_names
      if libs.length > 0
        Kernel::require 'dl'
        if RUBY_PLATFORM =~ /darwin/
          libs.each do |lib|
            DL.dlopen "lib#{lib}.dylib"
          end
        else
          libs.each do |lib|
            DL.dlopen "lib#{lib}.so"
          end
        end
      end
    end
  end
end