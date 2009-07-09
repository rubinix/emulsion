require 'rubygems'
require 'emulsion'
require 'ruby-prof'
#contents= File.open('objects/string.bin').read
#contents= File.open('objects/true.bin').read
contents= File.open('objects/max.bin').read
emulsion = Emulsion.new
#RubyProf.start
puts emulsion.parse contents
#result = RubyProf.stop
#printer = RubyProf::FlatPrinter.new(result)
#printer.print(STDOUT, 0)
