module Crystal
  class Type
    include Enumerable

    def metaclass
      @metaclass ||= Metaclass.new(self)
    end

    def instance_type
      self
    end

    def ==(other)
      equal?(other)
    end

    def eql?(other)
      self == other
    end

    def each
      yield self
    end

    def union?
      false
    end

    def nilable?
      false
    end

    def nil_type?
      false
    end

    def nilable_able?
      false
    end

    def pointer_type?
      false
    end

    def passed_as_self?
      true
    end

    def is_restriction_of?(type, owner)
      type && (equal?(type) || internal_full_name == type.internal_full_name || type.parents.any? { |parent| is_restriction_of?(parent, owner) })
    end

    def implements?(other_type)
      full_name == other_type.full_name
    end

    def filter_by(other_type)
      implements?(other_type) ? self : nil
    end

    def full_name
      name
    end

    def internal_full_name
      name
    end

    def to_s
      name
    end

    def self.merge(*types)
      types = types.compact
      return nil if types.empty?
      types.first.program.type_merge(*types)
    end

    def self.clone(types)
      types_context = {}
      types.map { |type| type.clone(types_context) }
    end

    def program
      @container.program
    end
  end

  class ContainedType < Type
    attr_accessor :name
    attr_accessor :container
    attr_reader :full_name

    def initialize(name, container)
      @name = name
      @container = container
      @full_name = @container && !@container.is_a?(Program) ? "#{@container.full_name}::#{@name}" : @name
    end

    def internal_full_name
      @full_name
    end
  end

  class Def
    def is_restriction_of?(other, owner)
      args.zip(other.args).each do |self_arg, other_arg|
        self_type = self_arg.type
        other_type = other_arg.type
        return false if self_type != nil && other_type == nil
        if self_type != nil && other_type != nil
          return false unless self_type.is_restriction_of?(other_type, owner)
        end
      end
      true
    end
  end

  module DefContainer
    def add_def(a_def)
      types = a_def.args.map(&:type)
      @defs[a_def.name] ||= {}
      @defs[a_def.name][[types, a_def.yields]] = a_def

      index = a_def.args.length - 1
      while index >= 0 && a_def.args[index].default_value
        @defs[a_def.name][[types[0 ... index], a_def.yields]] = a_def
        index -= 1
      end

      a_def
    end

    def lookup_def(name, args, yields, owner = self)
      defs = @defs[name]
      error_matches = defs.values if defs
      if defs
        if args
          matches = defs.select do |def_types_and_yields, a_def|
            def_types, def_yields = def_types_and_yields
            next false if def_yields != yields
            next false if def_types.length != args.length
            args.zip(def_types).all? { |arg, def_type| !def_type || def_type.is_restriction_of?(arg.type, owner) }
          end
          return matches.first[1] if matches.length == 1

          error_matches = matches.values if matches.length > 0

          matches = matches.values
          minimals = matches.select do |match|
            matches.all? { |m| m.equal?(match) || m.is_restriction_of?(match, owner) }
          end
          return minimals[0] if minimals.length == 1

          error_matches = minimals if minimals.length > 0
        else
          return defs.first[1] if defs.length == 1
        end
      end

      if parents && !(name == 'new' && owner.is_a?(Metaclass))
        parents.each do |parent|
          result, errors = parent.lookup_def(name, args, yields, owner)
          return [result, errors] if result
        end
      end

      [nil, error_matches]
    end

    def lookup_first_def(name)
      defs = @defs[name]
      if defs && defs.length == 1
        return defs.first[1]
      end
      nil
    end

    def add_def_instance(name, arg_types, typed_def)
      @def_instances[[name] + arg_types.map(&:type_id)] = typed_def
    end

    def lookup_def_instance(name, arg_types)
      @def_instances[[name] + arg_types.map(&:type_id)]
    end

    def has_restricted_defs?(name)
      defs = @defs[name]
      (defs && defs.keys.any? { |ary| ary[0].any? }) || (parents && parents.any? { |p| p.has_restricted_defs?(name) })
    end
  end

  class ModuleType < ContainedType
    include DefContainer

    attr_accessor :defs
    attr_accessor :types
    attr_accessor :parents

    def initialize(name, container = nil, parents = [])
      super(name, container)
      @parents = parents
      @defs = {}
      @def_instances = {}
      @types = {}
    end

    def include(mod)
      @parents.insert 0, mod unless @parents.any? { |parent| parent.equal?(mod) }
    end

    def implements?(other_type)
      super || parents.any? { |parent| parent.implements?(other_type) }
    end

    def lookup_type(names, already_looked_up = {})
      return nil if already_looked_up[type_id]
      already_looked_up[type_id] = true

      type = self
      names.each do |name|
        type = type.types[name]
        break unless type
      end

      return type if type

      parents.each do |parent|
        match = parent.lookup_type(names, already_looked_up)
        return match if match
      end

      container ? container.lookup_type(names, already_looked_up) : nil
    end
  end

  class ClassType < ModuleType
    def initialize(name, parent_type, container = nil)
      super(name, container, parent_type ? [parent_type] : [])
    end

    def superclass
      @parents.find { |parent| parent.is_a?(ClassType) }
    end
  end

  class PrimitiveType < ClassType
    attr_reader :llvm_type
    attr_reader :llvm_size

    def initialize(name, parent_type, llvm_type, llvm_size, container = nil)
      super(name, parent_type, container)
      @llvm_type = llvm_type
      @llvm_size = llvm_size
    end

    def nil_type?
      @nil_type ||= name == 'Nil'
    end

    def llvm_name
      name
    end

    def clone(*)
      self
    end
  end

  class ObjectType < ClassType
    attr_accessor :instance_vars
    attr_accessor :generic
    attr_accessor :string_rep
    attr_reader :hash
    @@id = 0

    def initialize(name, parent_type = nil, container = nil)
      super
      @instance_vars = {}
      @hash = name.hash
    end

    def metaclass
      @metaclass ||= begin
        metaclass = Metaclass.new(self)
        metaclass.add_def Def.new('allocate', [], Allocate.new(self))
        metaclass
      end
    end

    def has_instance_var?(name)
      @instance_vars[name]
    end

    def lookup_instance_var(name)
      @instance_vars[name] ||= Var.new name
    end

    def ==(other)
      equal?(other) || (generic && (structurally_equal?(other) || (other.is_a?(UnionType) && other == self)))
    end

    def structurally_equal?(other)
      other.is_a?(ObjectType) && name == other.name && instance_vars == other.instance_vars
    end

    def llvm_type
      @llvm_type ||= LLVM::Pointer(llvm_struct_type)
    end

    def llvm_size
      Crystal::Program::POINTER_SIZE
    end

    def llvm_struct_type
      unless @llvm_struct_type
        @llvm_struct_type = LLVM::Struct(llvm_name)
        @llvm_struct_type.element_types = @instance_vars.values.map(&:llvm_type)
      end
      @llvm_struct_type
    end

    def llvm_name
      if generic
        @id ||= (@@id += 1)
        "#{name}#{@id}"
      else
        name
      end
    end

    def nilable_able?
      true
    end

    def index_of_instance_var(name)
      @instance_vars.keys.index(name)
    end

    def clone(types_context = {})
      return self if !generic && Crystal::GENERIC

      obj = types_context[type_id] and return obj

      obj = types_context[type_id] = ObjectType.new name, @parent_type, @container
      obj.instance_vars = Hash[instance_vars.map do |name, var|
        cloned_var = var.clone
        cloned_var.type = var.type.clone(types_context) if var.type
        cloned_var.bind_to cloned_var
        [name, cloned_var]
      end]
      obj.defs = defs
      obj.types = types
      obj.parents = parents
      obj.generic = generic
      obj.string_rep = string_rep
      obj
    end

    def to_s
      return name unless generic
      return @to_s if @to_s
      if string_rep
        @to_s = string_rep.call(self)
        if @to_s
          to_s, @to_s = @to_s, nil
          return to_s
        end
      end
      @to_s = "..."
      instance_vars_to_s = instance_vars.map {|name, var| "#{name}: #{var.type}"}.join ', '
      @to_s = nil
      "#{name}<#{instance_vars_to_s}>"
    end
  end

  class PointerType < ClassType
    attr_accessor :var

    def initialize(parent_type = nil, container = nil, var = Var.new('var'))
      super("Pointer", parent_type, container)
      @var = var
    end

    def ==(other)
      equal?(other) || (other.is_a?(PointerType) && var.type == other.var.type) || (other.is_a?(UnionType) && other == self)
    end

    def hash
      1
    end

    def clone(types_context = {})
      pointer = types_context[type_id] and return pointer

      cloned_var = var.clone

      pointer = types_context[type_id] = PointerType.new @parent_type, @container, cloned_var
      pointer.var.type = var.type.clone(types_context)
      pointer.defs = defs
      pointer.types = types
      pointer.parents = parents
      pointer
    end

    def full_name
      if @var.type
        "#{@var.type.full_name}*"
      else
        super
      end
    end

    def nilable_able?
      true
    end

    def pointer_type?
      true
    end

    def to_s
      "Pointer<#{var.type}>"
    end

    def llvm_type
      @llvm_type ||= var.type.is_a?(StructType) ? var.type.llvm_type : LLVM::Pointer(var.type.llvm_type)
    end

    def llvm_name
      @llvm_name ||= "Pointer<#{var.type.llvm_name}>"
    end

    def llvm_size
      Crystal::Program::POINTER_SIZE
    end
  end

  class UnionType < Type
    attr_reader :types

    def initialize(*types)
      @types = types
    end

    def implements?(other_type)
      raise "'implements?' shouln't be invoked on a UnionType"
    end

    def filter_by(other_type)
      filtered_types = @types.map { |type| type.filter_by(other_type) }.compact
      case filtered_types.length
      when 0
        nil
      when 1
        filtered_types[0]
      else
        UnionType.new(*filtered_types)
      end
    end

    def nilable?
      @nilable ||= (@types.length == 2 &&
        (@types[0].nil_type? && types[1].nilable_able? && types[1] ||
         @types[1].nil_type? && types[0].nilable_able? && types[0]))
    end

    def nilable_type
      @nilable
    end

    def union?
      !nilable?
    end

    def set
      @set ||= types.to_set
    end

    def llvm_type
      unless @llvm_type
        if nilable?
          @llvm_type = nilable_type.llvm_type
        else
          @llvm_type = LLVM::Struct(llvm_name)
          @llvm_type.element_types = [LLVM::Int, llvm_value_type]
        end
      end
      @llvm_type
    end

    def llvm_name
      "[#{types.map(&:llvm_name).join ', '}]"
    end

    def llvm_size
      @llvm_size ||= llvm_value_size + 4
    end

    def llvm_value_type
      @llvm_value_type ||= LLVM::Type.array(LLVM::Int, llvm_value_size.fdiv(LLVM::Int.type.width / 8).ceil)
    end

    def llvm_value_size
      @llvm_value_size ||= @types.map(&:llvm_size).max
    end

    def index_of_type(type)
      @types.index type
    end

    def parents
      []
    end

    def each(&block)
      types.each(&block)
    end

    def hash
      @hash ||= set.hash
    end

    def ==(other)
      return true if equal?(other)
      set = set()
      (other.is_a?(UnionType) && set == other.set) || (!other.is_a?(UnionType) && set.length == 1 && types[0] == other)
    end

    def clone(types_context = {})
      cloned = types_context[object_id] and return cloned
      types_context[object_id] = UnionType.new(*types.map { |type| type.clone(types_context) })
    end

    def program
      @types[0].program
    end

    def name
      "Union"
    end

    def to_s
      "Union[#{types.join ', '}]"
    end
  end

  class Metaclass < ModuleType
    attr_reader :name
    attr_reader :type

    def initialize(type)
      super("#{type.full_name}:Class", type.container)
      @type = type
      add_def Def.new('name', [], StringLiteral.new(type.full_name))
      add_def Def.new('simple_name', [], StringLiteral.new(type.name))
      add_def Def.new('inspect', [], Call.new(nil, 'to_s'))
      add_def Def.new('to_s', [], Call.new(nil, 'name'))
    end

    def parents
      type.parents ? type.parents.map(&:metaclass) : nil
    end

    def instance_type
      type
    end

    def lookup_type(names)
      instance_type.lookup_type(names)
    end

    def llvm_type
      LLVM::Int
    end

    def llvm_name
      name
    end

    def llvm_size
      4
    end

    def full_name
      name
    end

    def to_s
      name
    end
  end

  class LibType < ModuleType
    attr_accessor :libname

    def initialize(name, libname = nil, container = nil)
      super(name, container)
      @libname = libname
    end

    def metaclass
      self
    end

    def fun(name, real_name, args, return_type, varargs)
      instance = add_def External.new(name, args)
      instance.real_name = real_name
      instance.varargs = varargs
      instance.owner = self
      instance.type = return_type
    end

    def passed_as_self?
      false
    end

    def ==(other)
      other.is_a?(LibType) && other.name == name && other.libname == libname
    end

    def to_s
      "LibType(#{name}, #{libname})"
    end
  end

  class TypeDefType < ContainedType
    attr_accessor :type

    def initialize(name, type, container = nil)
      super(name, container)
      @type = type
    end

    def ==(other)
      other.is_a?(TypeDefType) && other.name == name && other.type == type
    end

    def llvm_type
      type.llvm_type
    end

    def llvm_name
      type.llvm_name
    end

    def llvm_size
      type.llvm_size
    end

    def nilable_able?
      type.nilable_able?
    end

    def pointer_type?
      type.pointer_type?
    end

    def clone(*)
      self
    end

    def to_s
      name
    end
  end

  class StructType < ContainedType
    include DefContainer

    attr_accessor :vars
    attr_accessor :defs

    def initialize(name, vars, container = nil)
      super(name, container)
      @name = name
      @vars = Hash[vars.map { |var| [var.name, var] }]
      @defs = {}
      @def_instances = {}
      @vars.values.each do |var|
        add_def Def.new("#{var.name}=", [Arg.new_with_type('value', var.type)], StructSet.new(var.name))
        add_def Def.new(var.name, [], StructGet.new(var.name))
      end
    end

    def parents
      nil
    end

    def metaclass
      @metaclass ||= begin
        metaclass = Metaclass.new(self)
        metaclass.add_def Def.new('new', [], StructAlloc.new(self))
        metaclass
      end
    end

    def llvm_name
      name
    end

    def llvm_type
      @llvm_type ||= LLVM::Pointer(llvm_struct_type)
    end

    def llvm_size
      Crystal::Program::POINTER_SIZE
    end

    def llvm_struct_type
      unless @llvm_struct_type
        @llvm_struct_type = LLVM::Struct(llvm_name)
        @llvm_struct_type.element_types = @vars.values.map(&:llvm_type)
      end
      @llvm_struct_type
    end

    def index_of_var(name)
      @vars.keys.index(name)
    end

    def ==(other)
      other.is_a?(StructType) && other.name == name && other.vars == vars
    end

    def clone(*)
      self
    end

    def to_s
      return @to_s if @to_s
      @to_s = "..."
      vars_to_s = vars.map {|name, var| "#{name}: #{var.type}"}.join ', '
      @to_s = nil
      "#{name}<#{vars_to_s}>"
    end
  end

  class Const < ContainedType
    attr_accessor :value

    def initialize(name, value, container = nil)
      super(name, container)
      @value = value
    end

    def to_s
      "#{full_name} = #{value}"
    end
  end

  class SelfType
    def self.is_restriction_of?(type, owner)
      owner.is_restriction_of?(type, owner)
    end

    def self.full_name
      "self"
    end

    def self.parents
      []
    end
  end

  class ProxyType < Type
    attr_accessor :mod
    attr_accessor :target_type
    attr_accessor :node
    attr_accessor :type_vars
    attr_accessor :dead

    undef metaclass
    undef instance_type
    undef each
    undef union?
    undef nilable?
    undef nil_type?
    undef nilable_able?
    undef pointer_type?
    undef passed_as_self?
    undef is_restriction_of?
    undef implements?
    undef filter_by
    undef full_name
    undef internal_full_name

    def initialize(mod, target_type, node, type_vars)
      @mod = mod
      @target_type = target_type
      @node = node
      @type_vars = type_vars
      @type_vars.each do |name, type_var|
        type_var.add_observer self
      end
    end

    def program
      @target_type.program
    end

    def update(from)
      return if dead

      type_var_types = Hash[type_vars.map { |k, v| [k, v.type] }]
      type = mod.lookup_generic_type(target_type, type_var_types)
      return if type.equal?(target_type)

      self.dead = true
      proxy = ProxyType.new(mod, type, node, @type_vars)
      node.type = proxy
    end

    def propagate
    end

    def ==(other)
      other = other.target_type if other.is_a?(ProxyType)
      @target_type == other
    end

    def hash
      @target_type.hash
    end

    def eql?(other)
      other = other.target_type if other.is_a?(ProxyType)
      @target_type.eql?(other)
    end

    def equal?(other)
      other = other.target_type if other.is_a?(ProxyType)
      @target_type.equal?(other)
    end

    def is_a?(type)
      type == ProxyType || @target_type.is_a?(type)
    end

    def type_id
      @target_type.type_id
    end

    def respond_to?(name)
      name == :node || name == :target_type || @target_type.respond_to?(name)
    end

    def clone(*args)
      ProxyType.new(@target_type, @node, @type_vars)
    end

    def to_s
      if dead
        "DEAD(#{@target_type})"
      else
      "Proxy(#{@target_type})"
    end
    end

    def method_missing(name, *args, &block)
      @target_type.send name, *args, &block
    end
  end
end