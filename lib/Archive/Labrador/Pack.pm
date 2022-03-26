package Archive::Labrador::Pack;
use strict;

# Non-core dependencies
use Archive::Zip qw( :ERROR_CODES :CONSTANTS);
use Encode::Bitsy qw(isStrictName);

=head1 NAME

Archive::Labrador::Pack - Build new Labrador archives by packing files.

=head1 SYNOPSIS

  use Archive::Labrador::Pack;
  
  # Create a new pack object
  my $pack = Archive::Labrador::Pack->new();
  
  # Define MIME type mappings
  $pack->mapType('jpg', 'image/jpeg');
  $pack->mapType('png', 'image/png');
  $pack->mapBlankType('text/html');
  $pack->mapDefaultType('application/octet-stream');
  
  # Pack some files with no compression
  $pack->packFile("/~~Example Picture!~~.jpg", 'local/path/e', 0);
  $pack->packFile("/url/path/Another Picture.png", 'local/path/d', 0);
  
  # Pack some files with compression
  $pack->packFile("/articles/interesting", 'lib/interesting.htm', 1);
  
  # Pack some text strings (with compression)
  $pack->packString("/cliche/example.dat", "Hello, world!\n");
  
  # Sparse-pack with only a digest
  $pack->sparseDigest("/videos/dogs.avi", "5da4325cc...");
  
  # Pack some index files
  $pack->packIndexFile("/", 'html', 'local/path/index.html', 1);
  $pack->packIndexString("/status/", 'txt', "My status: OK!\n");
  $pack->sparseIndexDigest("/videos/", 'html', "997b4dca531...");
  
  # Assemble everything into a single labrador archive
  $pack->compile("path/to/output.lbz");

=head1 DESCRIPTION

Construct a new instance of this pack object, then define the MIME
mappings and what data will be packed inside, and finally compile
everything into a single Labrador archive.

After construction, the pack object starts out empty.  You make a series
of function calls to define its contents.  These function calls do not
take effect immediately, but rather are buffered.  When the compile
function is called, all the buffered calls are interpreted to build the
archive.

There are two basic kinds of things you can pack into a Labrador
archive.  The first kind of thing is a mapping from a file extension to
a MIME type.  The C<mapType> function is the regular function for adding
type mappings.  The C<mapBlankType> function can be used to establish a
MIME type for files that don't have an extension, and the
C<mapDefaultType> can be used to override the default MIME type that is
used for files that don't match any extension that is mapped within the
archive.

Calls to MIME type mapping functions can be made at any time before the
compile function is called.  You do B<not> need to map a particular file
extension before adding files with that extension, because calls are
buffered and only actually interpreted when the compile function is
called.

The other basic kind of thing you can pack into a Labrador archive is a
file that is part of the website that is being archived.  There are two
methods of file store: I<pack> and I<sparse>.  With the pack method, the
file data will be included within the Zip archive.  With the sparse
method, only a SHA-256 digest of the file data will be stored within the
Zip archive, and the file data is stored somewhere external from the
archive.

For the pack method, you can provide the file data either as a path to a
file on the local file system or as text data stored directly within a
string.  For the sparse method, you just provide the SHA-256 digest that
should be included in the archive; the actual file data does not need to
be available.

Another dimension to the storage functions is where the files are being
stored in the virtual file system.  The names and paths to files in the
local file system have nothing to do with the name and path of the file
objects stored in the website within the Labrador archive, and there are
no local file paths when data is provided in strings or as a digest.
Instead, you must explicitly declare where each file object will be
stored on the archived website with each storage function call.

There are two basic kinds of destination targets on the archived
website: regular pages and index pages.  Regular pages are accessed on
the website as URLs to files, while index pages are accessed on the
website as URLs to directories.

The distinctions given above leads to the following set of storage
functions:

                               Destination Target
                    +----------------+---------------------+
    Method   Source |    Regular     |        Index        |
  +========+========+================+=====================+
  |  PACK  |  File  | packFile()     | packIndexFile()     |
  |        | String | packString()   | packIndexString()   |
  +--------+--------+----------------+---------------------+
  | SPARSE | Digest | sparseDigest() | sparseIndexDigest() |
  +--------+--------+----------------+---------------------+

The website URL locations you provide may freely use Unicode and assume
case sensitivity, even though neither of these things are reliable for
Zip archives.  Labrador transparently uses Bitsy encoding within the
archive for all file and directory names.  For all the functions with an
index destination target, you must provide a file extension along with
the URL, which will determine the MIME type.  Finally, the C<packFile()>
function allows you to specify whether the data should be compressed
within the archive or not compressed.

See the documentation of each function below for further information.

=cut

# =========
# Constants
# =========

# Maximum number of characters in a Bitsy-encoded URL
#
my $MAX_URL = 16384;

=head1 CONSTRUCTOR

=over 4

=item B<Archive::Labrador::Pack->new()>

Construct a new Pack object instance.  The new instance always starts
out empty.

=cut

sub new {
  
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get invocant and parameters
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  
  # Define the new object and bless it
  my $self = { };
  bless($self, $class);
  
  # Define a "tmap" parameter that is a hash reference; this will store
  # mappings of file extensions (lowercase, no initial dot) to MIME
  # types, with the special "." type reserved for the catch-all type and
  # the special "-" type reserved for the default type
  $self->{'tmap'} = { };
  
  #
  # Define a "vfs" parameter that is a hash reference.  This will
  # represent the virtual file system that is being constructed within
  # the Labrador archive.
  #
  # Each key is either a file key or a folder key.  File keys are a
  # sequence of zero or more Bitsy-encoded, lowercased directory names
  # each followed by a forward slash, and then a required Bitsy-encoded,
  # lowercased file name.  Folder keys are a sequence of one or more
  # Bitsy-encoded, lowercased directory names each followed by a forward
  # slash.  It is easy to distinguish between the two key types:  file
  # keys never end with a forward slash while folder keys always end
  # with a forward slash.  Neither key type ever has a forward slash at
  # the beginning.
  #
  # Note that file and folder keys do NOT exactly match the encoded
  # names that will be used in the Labrador archive, because file and
  # folder keys have the case of each letter normalized to lowercase,
  # while names in the Labrador archive may use both lowercase and
  # uppercase, preserving original case as much as possible.
  #
  # Folder keys always map to a string value containing their path
  # without case normalization applied.  Whenever a non-sparse file is
  # added to the virtual file system, a check is made that each
  # directory in the trail (excluding the root directory) has a folder
  # key, and any missing folder keys are added as new entries.  For
  # example:
  #
  #   New file: /example/path/to/file.txt
  #   Requires the following folder keys to be added if not present:
  #     /example/
  #     /example/path/
  #     /example/path/to/
  #
  # Sparse files that are being added by digest only do NOT require any
  # folder keys, since those files will not actually be stored directly
  # in the archive.
  #
  # Note also that index pages corresponding to URL directories are NOT
  # represented by folder keys but rather by file keys, using the same
  # special "index" encoding described in the Labrador spec.
  #
  # File keys always map to a hash reference that represents the file
  # object.  The hash reference always has the following property:
  #
  #   - url : the encoded URL path to the file (not case normalized)
  # 
  # This property is the same as the file key, except that it may also
  # contain uppercase letters.
  #
  # File objects that are being packed from a file in the local file
  # system will have the following additional properties:
  #
  #   - path : the path to the source file in the local file system
  #   - compress : 1 to pack with compression, 0 for no compression
  #
  # File objects that are being packed from a string will have the
  # following additional property:
  #
  #   - text : string containing raw octets of data
  # 
  # File objects that are being added with the sparse method will have
  # the following additional property:
  #
  #   - sha256 : the SHA-256 digest as a string of base-16 characters
  #
  $self->{'vfs'} = { };
  
  # Return the new object
  return $self;
}

=back

=head1 INSTANCE METHODS

=over 4

=item B<object->mapType(ext, mime)>

Establish a mapping from a particular file extension to a MIME type.

The C<ext> parameter is the file extension that is being mapped.  It
will automatically be converted to lowercase by this function.  If "a."
were to be prefixed to the given extension, the result must be a
StrictName according to Bitsy.  The extension must not include the
leading dot, but for compound types you must include internal dots.
That is, use "jpeg" and "tar.gz" as the format.

The C<mime> parameter must be a sequence of one or more US-ASCII
printing characters from the range [U+0020, U+007E], with the
restriction that neither the first nor last character may be a space.
Otherwise, all values are allowed.  This should be a valid MIME type,
such as "image/jpeg"

If the given extension is already present in the map, its mapping is
replaced with the new MIME type value.

=cut

sub mapType {
  
  # Check parameter count
  ($#_ == 2) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self = shift;
  my $ext = shift;
  my $mime = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($ext)) or die "Wrong parameter type, stopped";
  $ext = "$ext";
  
  (not ref($mime)) or die "Wrong parameter type, stopped";
  $mime = "$mime";
  
  # Convert extension to lowercase and check that when "a." is prefixed
  # the result is a StrictName
  $ext =~ tr/A-Z/a-z/;
  (isStrictName('a.' . $ext)) or die "Invalid extension, stopped";
  
  # Check that MIME type value is non-empty and has only US-ASCII
  # printing characters
  ($mime =~ /^[\x{20}-\x{7e}]+$/) or
    die "Invalid MIME type value, stopped";
  
  # Check that MIME type value neither begins nor ends with space
  ((not ($mime =~ /^ /)) and (not ($mime =~ / $/))) or
    die "MIME type value may not begin or end with space, stopped";
  
  # Add or replace the mapping
  $self->{'tmap'}->{$ext} = $mime;
}

=item B<object->mapBlankType(mime)>

Establish a MIME mapping for files that don't have any extension at all.

The C<mime> parameter must be a sequence of one or more US-ASCII
printing characters from the range [U+0020, U+007E], with the
restriction that neither the first nor last character may be a space.
Otherwise, all values are allowed.  This should be a valid MIME type,
such as "image/jpeg"

If a blank type mapping is already present in the map, its mapping is
replaced with the new MIME type value.

The blank type will apply to all files whose Bitsy-encoded name contains
no periods.

=cut

sub mapBlankType {
  
  # Check parameter count
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self = shift;
  my $mime = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($mime)) or die "Wrong parameter type, stopped";
  $mime = "$mime";
  
  # Check that MIME type value is non-empty and has only US-ASCII
  # printing characters
  ($mime =~ /^[\x{20}-\x{7e}]+$/) or
    die "Invalid MIME type value, stopped";
  
  # Check that MIME type value neither begins nor ends with space
  ((not ($mime =~ /^ /)) and (not ($mime =~ / $/))) or
    die "MIME type value may not begin or end with space, stopped";
  
  # Add or replace the mapping
  $self->{'tmap'}->{'-'} = $mime;
}

=item B<object->mapDefaultType(mime)>

Establish a MIME mapping for files that don't match any of the other
established mappings.

The C<mime> parameter must be a sequence of one or more US-ASCII
printing characters from the range [U+0020, U+007E], with the
restriction that neither the first nor last character may be a space.
Otherwise, all values are allowed.  This should be a valid MIME type,
such as "image/jpeg"

If a default type mapping is already present in the map, its mapping is
replaced with the new MIME type value.  If no default type mapping is
explicitly established with this function, the implicit default will be
"application/octet-stream"

=cut

sub mapDefaultType {
  
  # Check parameter count
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self = shift;
  my $mime = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($mime)) or die "Wrong parameter type, stopped";
  $mime = "$mime";
  
  # Check that MIME type value is non-empty and has only US-ASCII
  # printing characters
  ($mime =~ /^[\x{20}-\x{7e}]+$/) or
    die "Invalid MIME type value, stopped";
  
  # Check that MIME type value neither begins nor ends with space
  ((not ($mime =~ /^ /)) and (not ($mime =~ / $/))) or
    die "MIME type value may not begin or end with space, stopped";
  
  # Add or replace the mapping
  $self->{'tmap'}->{'.'} = $mime;
}

=item B<object->packFile(url, path, compress)>

Register a file that will be packed into the Labrador archive.

This function does not actually read the file yet.  Instead, it simply
records the registration internally in the object.  The file will
actually be read and packed when the compile function is called.

url is a string that gives the URL that this file should be associated
with in the archived website.  The passed URL must B<not> be
Bitsy-encoded.  You may use Unicode in the passed url string.  The url
string must be non-empty and neither begin nor end with forward slash
characters.  Furthermore, no forward slash character may be followed
immediately with another forward slash character.  If there are no
forward slash characters, the whole url is a file name in the root
directory of the website.  Otherwise, the url is a sequence of directory
names each terminated by a forward slash, and then the file name at the
end.

The url will be split into a sequence of zero or more directory names
and a file name.  Each directory and file name must successfully encode
into Bitsy, and the total length of the Bitsy-encoded path when
reassembled with forward slash separators must not exceed the MAX_URL
character limit defined within this module.

Starting at the root directory of the website and proceeding folder by
folder to the parent folder of the file named by the URL, each folder
path along the way when case-normalized to lowercase must not match any
existing file in the virtual file system.  Folder keys will be added for
each folder path along the way if they do not already exist.

The full Bitsy-encoded URL path to the file must not match any folder
key when a forward slash is appended to it.  Also, the full
Bitsy-encoded URL path must not already exist as a file in the virtual
file system.

It is not necessary to declare file extension to MIME type mappings
before adding files with that extension.  You can establish MIME type
mappings at any point before compile is called.  All that matters is the
state of the MIME type mapping at the time the compile function is
called.

path is a string that gives the path to the file on the local file
system that will be read when the compile function is called.  The local
path to the file has no effect whatsoever on the URL stored within the
file or the MIME type of the file.  This function will merely check that
the path refers to a regular file using the -f operator.

compress must be an integer that is either 1 or 0.  If it is 1, then the
file will be compressed when packed into the archive.  If it is 0, then
the file will not be compressed when packed into the archive.
Generally, you should compress files for efficiency.  However, if a file
is already compressed (such as a JPEG or PNG image), then there is not
much point to compressing it again, so compression is better disabled
for those types of files.

=cut

sub packFile {
  
  # Check parameter count
  ($#_ == 3) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self     = shift;
  my $url      = shift;
  my $path     = shift;
  my $compress = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($url)) or die "Wrong parameter type, stopped";
  $url = "$url";
  
  (not ref($path)) or die "Wrong parameter type, stopped";
  $path = "$path";
  
  (not ref($compress)) or die "Wrong parameter type, stopped";
  (int($compress) == $compress) or die "Wrong parameter type, stopped";
  $compress = int($compress);
  (($compress == 0) or ($compress == 1)) or
    die "Wrong parameter type, stopped";
  
  # Check that URL is not empty, that it doesn't begin nor end with
  # forward slashes, and that no forward slash immediately follows
  # another forward slash
  (length($url) > 0) or die "Invalid URL, stopped";
  ((not ($url =~ /^\//)) and (not ($url =~ /\/$/)) and
    (not ($url =~ /\/\//))) or die "Invalid URL, stopped";
  
  # Split URL into directory trail and file name
  my @dtr;
  my $fname;
  if ($url =~ /\//) {
    # URL has at least one forward slash, so begin by splitting by
    # slashes
    @dtr = split /\//, $url;
    
    # Should have at least two components
    ($#dtr > 0) or die "Unexpected";
    
    # The last component is actually the file name
    $fname = pop @dtr;
    
  } else {
    # URL has no foward slash, so leave directory trail empty and set
    # file name to whole passed URL
    $fname = $url;
  }
  
  # Encode all directory names and the file name to Bitsy
  eval {
    for my $d (@dtr) {
      $d = encodeBitsy($d);
    }
    $fname = encodeBitsy($fname);
    
  };
  if ($@) {
    die "Bitsy encoding failed for URL component: $@";
  }
  
  # Within the directory trail, get the index of the first element that
  # does not have a directory key, also checking that no directories
  # conflict with existing files; if everything in the directory trail
  # is already present as a directory key, set this index to the length
  # of the directory trail array
  my $newdir_i;
  for($newdir_i = 0; $newdir_i <= $#dtr; $newdir_i++) {
    # Assemble the URL path to the current directory in the trail
    my $upath = join '/', @dtr[0 .. $newdir_i];
    
    # Make the assembled URL path lowercase
    $upath =~ tr/A-Z/a-z/;
    
    # Check first whether the assembled URL path refers to a file within
    # the virtual file system
    (not exists $self->{'vfs'}->{$upath}) or
      die "Directory conflicts with existing file, stopped";
    
    # Check whether the assembled URL path with a forward slash appended
    # already exists in the virtual file system
    if (not exists $self->{'vfs'}->{$upath . '/'}) {
      # We found the first directory index that doesn't exist, so leave
      # the loop
      last;
    }
  }
  
  # @@TODO:
}

=back

=head1 AUTHOR

Noah Johnson, C<noah.johnson@loupmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 Multimedia Data Technology Inc.

MIT License:

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut

# Finish with something that evaluates to true
#
1;
