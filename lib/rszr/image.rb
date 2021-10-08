module Rszr
  class Image
    extend Identification
    include Buffered
    include Orientation
    
    class << self

      def load(path, autorotate: Rszr.autorotate, **opts)
        path = path.to_s
        raise FileNotFound unless File.exist?(path)
        image = _load(path)
        autorotate(image, path) if autorotate
        image
      end
      alias :open :load
      
      def load_data(data, autorotate: Rszr.autorotate, **opts)
        raise LoadError, 'Unknown format' unless format = identify(data)
        with_tempfile(format, data) do |file|
          load(file.path, autorotate: autorotate, **opts)
        end
      end

    end

    def dimensions
      [width, height]
    end
    
    def format
      fmt = _format
      fmt == 'jpg' ? 'jpeg' : fmt
    end
    
    def format=(fmt)
      fmt = fmt.to_s if fmt.is_a?(Symbol)
      self._format = fmt
    end

    def inspect
      fmt = format
      fmt = " #{fmt.upcase}" if fmt
      "#<#{self.class.name}:0x#{object_id.to_s(16)} #{width}x#{height}#{fmt}>"
    end

    module Transformations
      def resize(*args)
        _resize(false, *calculate_size(*args))
      end

      def resize!(*args)
        _resize(true, *calculate_size(*args))
      end

      def crop(x, y, width, height)
        _crop(false, x, y, width, height)
      end

      def crop!(x, y, width, height)
        _crop(true, x, y, width, height)
      end
      
      def turn(orientation)
        dup.turn!(orientation)
      end

      def turn!(orientation)
        orientation = orientation.abs + 2 if orientation.negative?
        _turn!(orientation % 4)
      end
    
      def rotate(deg)
        _rotate(false, deg.to_f * Math::PI / 180.0)
      end
    
      def rotate!(deg)
        _rotate(true, deg.to_f * Math::PI / 180.0)
      end
      
      # horizontal
      def flop
        dup.flop!
      end
      
      # vertical
      def flip
        dup.flip!
      end
    
      def sharpen(radius)
        dup.sharpen!(radius)
      end
    
      def sharpen!(radius)
        raise ArgumentError, 'illegal radius' if radius < 0
        _sharpen!(radius)
      end
    
      def blur(radius)
        dup.blur!(radius)
      end
    
      def blur!(radius)
        raise ArgumentError, 'illegal radius' if radius < 0
        _sharpen!(-radius)
      end
      
      def filter(filter_expr)
        dup.filter!(filter_expr)
      end
      
      def brighten!(value, r: nil, g: nil, b: nil, a: nil)
        raise ArgumentError, 'illegal brightness' if value > 1 || value < -1
        filter!("colormod(brightness=#{value.to_f});")
      end
      
      def brighten(*args)
        dup.brighten!(*args)
      end
      
      def contrast!(value, r: nil, g: nil, b: nil, a: nil)
        raise ArgumentError, 'illegal contrast (must be > 0)' if value < 0
        filter!("colormod(contrast=#{value.to_f});")
      end
      
      def contrast(*args)
        dup.contrast!(*args)
      end
      
      def gamma!(value, r: nil, g: nil, b: nil, a: nil)
        #raise ArgumentError, 'illegal gamma (must be > 0)' if value < 0
        filter!("colormod(gamma=#{value.to_f});")
      end
      
      def gamma(*args)
        dup.gamma!(*args)
      end
    end
    
    include Transformations

    def save(path, format: nil, quality: nil)
      format ||= format_from_filename(path) || self.format || 'jpg'
      raise ArgumentError, "invalid quality #{quality.inspect}" if quality && !(0..100).cover?(quality)
      ensure_path_is_writable(path)
      _save(path.to_s, format.to_s, quality)
    end
    
    def save_data(format: nil, quality: nil)
      format ||= self.format || 'jpg'
      with_tempfile(format) do |file|
        save(file.path, format: format, quality: quality)
        file.rewind
        file.read
      end
    end

    private
    
    # 0.5               0 < scale < 1
    # 400, 300          fit box
    # 400, :auto        fit width, auto height
    # :auto, 300        auto width, fit height
    # 400, 300, crop: :center_middle
    # 400, 300, background: rgba
    # 400, 300, skew: true
    
    def calculate_size(*args, crop: nil, skew: nil)
      options = args.last.is_a?(Hash) ? args.pop : {}
      #assert_valid_keys options, :crop, :background, :skew  #:extend, :width, :height, :max_width, :max_height, :box
      original_width, original_height = width, height
      x, y, = 0, 0
      if args.size == 1
        scale = args.first
        raise ArgumentError, "scale factor #{scale.inspect} out of range" unless scale > 0 && scale < 1
        new_width = original_width.to_f * scale
        new_height = original_height.to_f * scale
      elsif args.size == 2
        box_width, box_height = args
        if :auto == box_width && box_height.is_a?(Numeric)
          new_height = box_height
          new_width = box_height.to_f / original_height.to_f * original_width.to_f
        elsif box_width.is_a?(Numeric) && :auto == box_height
          new_width = box_width
          new_height = box_width.to_f / original_width.to_f * original_height.to_f
        elsif box_width.is_a?(Numeric) && box_height.is_a?(Numeric)
          if skew
            new_width, new_height = box_width, box_height
          elsif crop
            # TODO: calculate x, y offset if crop
          else
            scale = original_width.to_f / original_height.to_f
            box_scale = box_width.to_f / box_height.to_f
            if scale >= box_scale # wider
              new_width = box_width
              new_height = original_height.to_f * box_width.to_f / original_width.to_f
            else # narrower
              new_height = box_height
              new_width = original_width.to_f * box_height.to_f / original_height.to_f
            end
          end
        else
          raise ArgumentError, "unconclusive arguments #{args.inspect} #{options.inspect}"
        end
      else
        raise ArgumentError, "wrong number of arguments (#{args.size} for 1..2)"
      end
      [x, y, original_width, original_height, new_width.round, new_height.round]
    end

    def format_from_filename(path)
      File.extname(path)[1..-1].to_s.downcase
    end
    
    def ensure_path_is_writable(path)
      path = Pathname.new(path)
      path.dirname.realpath.writable?
    rescue Errno::ENOENT => e
      raise SaveError, 'Non-existant path component'
    rescue SystemCallError => e
      raise SaveError, e.message
    end

    def assert_valid_keys(hsh, *valid_keys)
      if unknown_key = (hsh.keys - valid_keys).first
        raise ArgumentError.new("Unknown key: #{unknown_key.inspect}. Valid keys are: #{valid_keys.map(&:inspect).join(', ')}")
      end
    end
    
  end
end
