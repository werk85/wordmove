module Wordmove
  module SqlAdapter
    class Default
      attr_writer :sql_content
      attr_reader :sql_path, :source_config, :dest_config

      def initialize(sql_path, source_config, dest_config)
        @sql_path = sql_path
        @source_config = source_config
        @dest_config = dest_config
      end

      def sql_content
        @sql_content ||= begin
          content = File.open(sql_path, 'rb').read
          # Try UTF-8 first
          content.force_encoding('UTF-8')
          # Fall back to binary if not valid UTF-8
          content.force_encoding('BINARY') unless content.valid_encoding?
          content
        end
      end

      def adapt!
        replace_vhost!
        replace_wordpress_path!
        write_sql!
      end

      def replace_vhost!
        source_vhost = source_config[:vhost]
        dest_vhost = dest_config[:vhost]
        replace_field!(source_vhost, dest_vhost)
      end

      def replace_wordpress_path!
        source_path = source_config[:wordpress_absolute_path] || source_config[:wordpress_path]
        dest_path = dest_config[:wordpress_absolute_path] || dest_config[:wordpress_path]
        replace_field!(source_path, dest_path)
      end

      def replace_field!(source_field, dest_field)
        return false unless source_field && dest_field

        # Ensure sql_content is loaded
        sql_content unless @sql_content

        # Ensure source and dest fields match the content encoding
        source_field = source_field.dup.force_encoding(@sql_content.encoding)
        dest_field = dest_field.dup.force_encoding(@sql_content.encoding)

        serialized_replace!(source_field, dest_field)
        simple_replace!(source_field, dest_field)
      end

      def serialized_replace!(source_field, dest_field)
        length_delta = source_field.length - dest_field.length

        sql_content.gsub!(/s:(\d+):(\\*['"])(.*?)\2;/) do |match|
          length = Regexp.last_match(1).to_i
          delimiter = Regexp.last_match(2)
          string = Regexp.last_match(3)

          # Force all parts to the same encoding as sql_content
          string = string.dup.force_encoding(@sql_content.encoding)
          source_pattern = Regexp.escape(source_field).force_encoding(@sql_content.encoding)
          dest_field_encoded = dest_field.dup.force_encoding(@sql_content.encoding)

          begin
            if string.include?(source_field)
              string.gsub!(/#{source_pattern}/) do |_|
                length -= length_delta
                dest_field_encoded
              end
              %(s:#{length}:#{delimiter}#{string}#{delimiter};)
            else
              match
            end
          rescue StandardError
            # Return original match if any error occurs
            match
          end
        end
      end

      def simple_replace!(source_field, dest_field)
        sql_content.gsub!(source_field, dest_field)
      end

      def write_sql!
        File.open(sql_path, 'w') { |f| f.write(sql_content) }
      end
    end
  end
end
