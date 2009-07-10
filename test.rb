require 'rubygems'
require 'emulsion'
require 'ruby-prof'
#contents= File.open('objects/string.bin', 'rb').read
#contents= File.open('objects/true.bin', 'rb').read
#contents= File.open('objects/min.bin', 'rb').read FIX!
#contents= File.open('objects/max.bin', 'rb').read
#contents= File.open('objects/0.bin', 'rb').read
#contents= File.open('objects/largeMin.bin', 'rb').read FIX!
contents= File.open('objects/largeMax.bin', 'rb').read

emulsion = Emulsion.new
#RubyProf.start
puts emulsion.parse contents
#result = RubyProf.stop
#printer = RubyProf::FlatPrinter.new(result)
#printer.print(STDOUT, 0)
