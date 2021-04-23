require 'mkmf'
require 'rbconfig'

imlib2_config = with_config('imlib2-config', 'imlib2-config')

$CFLAGS << ' -DX_DISPLAY_MISSING ' << `#{imlib2_config} --cflags`.chomp
$LDFLAGS << ' ' << `#{imlib2_config} --libs`.chomp
$LDFLAGS.gsub!(/\ -lX11\ -lXext/, '') if RUBY_PLATFORM =~ /darwin/

unless find_header('Imlib2.h')
  abort 'imlib2 development headers are missing'
end

unless find_library('Imlib2', 'imlib_set_cache_size')
  abort 'Imlib2 is missing'
end

unless find_library('exif', 'exif_data_new_from_file')
  abort 'libexif is missing'
end

have_library('exif')
have_header('libexif/exif-data.h')

create_makefile 'rszr/rszr'
