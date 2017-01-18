# Example ruby chef_node_matrix.rb --row chef_environment --col chef_packages.chef.version
# Example ruby chef_node_matrix.rb --row chef_environment --col "platform,platform_version"
# Example ruby chef_node_matrix.rb --row platform --col platform_version
require 'chef'

class CommandParameters
	def get_options(args)
		options = {}
		opt_parser = OptionParser.new do |opts|
		  opts.banner = "Usage: #{__FILE__} [options]"

		  opts.on('-c', '--config CONFIG', 'The chef/knife configuration file') { |v| options[:configuration] = v }
		  opts.on('', '--row ROW_ATTRIBUTES', 'The node attribute used for rows') { |v| options[:row_attributes] = v }
		  opts.on('', '--col COL_ATTRIBUTES', 'The node attribute used for columns') { |v| options[:col_attributes] = v }
		  
		  opts.on("-h", "--help", "Prints out command help") do
			  puts opts
			  exit
		  end
		end

		opt_parser.parse!(args)
		options
	end
end

unless Hash.instance_methods.include?(:dig)
  class Hash
    # Add dig
    def dig(*path_elements)
      descend_hash(path_elements.join('.'))
    end
  
    private
    def descend_hash(dotted_path)
      parts = dotted_path.split('.', 2)
      match = self[parts.first]
      # End of the chain or cannot descend further
      if parts[1].nil? || match.nil?
        return match
      else
        return match.descend_hash(parts[1])
      end
    end
  end
end

def attributes_value(node_hash, attribute_paths)
  paths = attribute_paths.split(',')
  attribute_values = paths.map do | path |
    path_elements = path.split('.')
    node_hash.dig(*path_elements) || 'nil'
  end
end

def gather_node_data(row_attributes, col_attributes)
  matrix = Chef::Node.list.each_with_object({}) do |node, hsh|
    node_data = Chef::Node.load(node[0])
    node_data_hash = node_data.to_hash
    col_data = attributes_value(node_data_hash, col_attributes)
    row_data = attributes_value(node_data_hash, row_attributes)
    key = [col_data, row_data]
    hsh[key] = 0 unless hsh.key?(key)
    hsh[key] += 1
  end
end

def build_matrix(row_attributes, data_hash)
  # Create the matrix keys
  column_keys = data_hash.keys.map { |e| e.first }.uniq.sort
  row_keys = data_hash.keys.map { |e| e.last }.uniq.sort
  row_values = row_keys.map { |e| e.join(' ') }
  # Map out the data
  matrix = [([row_attributes] << column_keys).flatten]
  row_keys.each do | row |
    row_heading = row.join(' ')
    matrix_row = []
    column_keys.each do | col |
      lookup_key = [col, row]
      node_count = data_hash[lookup_key]
      node_count ||= '-'
      matrix_row << node_count
    end
    matrix << ([row_heading] << matrix_row).flatten
  end
  matrix
end

def show_report(row_attributes, col_attributes, matrix)
  # show report
  underline_length = row_attributes.length + col_attributes.length
  puts '-' * underline_length
  puts "#{row_attributes} / #{col_attributes}"
  puts '-' * underline_length
  col_key_max_length = matrix.map { |r| r[0].length }.max
  header_format = "%-#{col_key_max_length}s" + (' %15s' * (matrix[0].length - 1))
  row_format = "%-#{col_key_max_length}s" + (' %15s' * (matrix[0].length - 1))
  puts header_format % matrix[0]
  matrix[1..-1].each do |row|
    puts row_format % row
  end
  puts ''
end
	
options = CommandParameters.new.get_options(ARGV)
row_attributes = options[:row_attributes]
col_attributes = options[:col_attributes]

raise 'You must specify a row and a column!' if row_attributes.nil? || col_attributes.nil?

knife_config = options[:configuration] || "~/.chef/knife.rb"
Chef::Config.from_file(File.expand_path(knife_config))

puts "Will connect to Chef server at #{Chef::Config[:chef_server_url]}"
puts 'Retrieving nodes ...'
node_data = gather_node_data(row_attributes, col_attributes)

puts 'Done ... building matrix'
matrix = build_matrix(row_attributes, node_data)

puts 'Done ... showing result'
show_report(row_attributes, col_attributes, matrix)
