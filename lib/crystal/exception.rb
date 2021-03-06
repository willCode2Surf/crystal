module Crystal
  class Exception < StandardError
    def message(source = nil)
      to_s(source)
    end
  end

  class SyntaxException < Exception
    def initialize(message, line_number, column_number, filename)
      @message = message
      @line_number = line_number
      @column_number = column_number
      @filename = filename
    end

    def to_s(source = nil)
      if @filename
        str = "Syntax error in #{@filename}:#{@line_number}: #{@message}"
      else
        str = "Syntax error in line #{@line_number}: #{@message}"
      end

      if @filename && File.file?(@filename)
        source = File.read(@filename)
      end

      if source
        lines = source.lines.to_a
        line = lines[@line_number - 1]
        if line
          str << "\n\n"
          str << line.chomp
          str << "\n"
          str << (' ' * (@column_number - 1))
          str << '^'
          str << "\n"
        end
      end
      str
    end
  end

  class TypeException < Exception
    attr_accessor :node
    attr_accessor :inner

    def self.for_node(node, message, inner = nil)
      if node.respond_to?(:name)
        length = node.respond_to?(:name_length) ? node.name_length : node.name.length
        if node.respond_to?(:name_column_number)
          new message, node.line_number, node.name_column_number, node.filename, length, inner
        else
          new message, node.line_number, node.column_number, node.filename, length, inner
        end
      else
        new message, node.line_number, node.column_number, node.filename, nil, inner
      end
    end

    def initialize(message, line, column, filename, length = nil, inner = nil)
      @message = message
      @line = line
      @column = column
      @filename = filename
      @length = length
      @inner = inner
    end

    def to_s(source = nil)
      str = 'Error '
      append_to_s(str, source)
      str
    end

    def append_to_s(str, source)
      if @filename && File.file?(@filename)
        lines = File.readlines @filename
        str << "in #{@filename}:#{@line}: #{@message}"
      else
        lines = source ? source.lines.to_a : nil
        str << "in line #{@line}: #{@message}"
      end

      if lines && @line
        line = lines[@line - 1]
        if line
          str << "\n\n"
          str << line.chomp
          str << "\n"
          str << (' ' * (@column - 1))
          str << '^'
          if @length && @length > 0
            str << ('~' * (@length - 1))
          end
        end
      end
      str << "\n"
      if inner
        str << "\n"
        inner.append_to_s(str, source)
      end
    end
  end
end
