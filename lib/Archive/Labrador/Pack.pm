package Archive::Labrador::Pack;
use strict;

# Non-core dependencies
use Archive::Zip qw( :ERROR_CODES :CONSTANTS);
use Encode::Bitsy qw(decodeBitsy encodeBitsy isStrictName);

# @@TODO: change compression feature to be property of MIME type
# mappings

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

# Maximum number of characters in a Bitsy-encoded path
#
my $MAX_ZPATH = 1023;

# ===============
# Local functions
# ===============

# Return the encoded normalization of a name.
#
# The provided name must be a valid Bitsy-encoded name or a fault will
# occur during Bitsy decoding.
#
# Encoded normalization is defined in the Labrador spec.
#
# Parameters:
#
#   1 : string - the Bitsy-encoded name
#
# Return:
#
#   the encoded normalization of the name
#
sub encNormName {
  
  # Check parameter count
  ($#_ == 0) or die "Wrong parameter count, stopped";
  
  # Get parameters and check types
  my $str = shift;
  
  (not ref($str)) or die "Wrong parameter type, stopped";
  $str = "$str";
  
  # Convert uppercase letters to lowercase
  $str =~ tr/A-Z/a-z/;
  
  # Special handling for xq--index-x. escaping
  if ($str =~ /^xq--index-x\./) {
    return $str;
  }
  
  # If name is an index. style name, normalize extension to .i
  if ($str =~ /^index\./) {
    $str = 'index.i';
  }
  
  # Bitsy-decode to Unicode, and then re-encode in Bitsy
  $str = encodeBitsy(decodeBitsy($str));
  
  # Return normalized name
  return $str;
}

# Return the encoded normalization of a path.
#
# The provided path must not be empty, must not begin or end with a
# forward slash, and must not have two forward slashes in a row
# anywhere.  The path will be split into components with the forward
# slash as a separator (with a single component if there are no forward
# slashes).  Each component will then be encoded-normalized with
# encNormName(), and the rejoined path will then be returned.
#
# This function will verify that no component is "." or ".." and that
# for all but the last component, the component does not normalize to
# "index.i" with faults occuring if there are any problems.
#
# If the second parameter to this function indicates that this is the
# path for a directory, then this function will also check that the
# last component does not normalize to "index.i"
#
# Encoded normalization is defined in the Labrador spec.
#
# Parameters:
#
#   1 : string - the Bitsy-encoded path to normalize
#
#   2 : integer - zero if this is a file path, one if this is a
#   directory path
#
# Return:
#
#   the encoded normalization of the path
#
sub encNormPath {
  
  # Check parameter count
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $path     = shift;
  my $dir_flag = shift;
  
  (not ref($path)) or die "Wrong parameter type, stopped";
  $path = "$path";
  
  (not ref($dir_flag)) or die "Wrong parameter type, stopped";
  (int($dir_flag) == $dir_flag) or die "Wrong parameter type, stopped";
  $dir_flag = int($dir_flag);
  (($dir_flag == 0) or ($dir_flag == 1)) or
    die "Parameter value out of range, stopped";
  
  # Path must not be empty
  (length($path) > 0) or die "Invalid path, stopped";
  
  # Check slashes
  ((not ($path =~ /^\//)) and (not ($path =~ /\/$/)) and
      (not ($path =~ /\/\//))) or
    die "Invalid path, stopped";
  
  # Split into components
  my @pa;
  if ($path =~ /\//) {
    @pa = split /\//, $path;
  } else {
    push @pa, ($path);
  }
  
  # Transform and check the components
  for(my $i = 0; $i <= $#pa; $i++) {
    # Get current component
    my $c = $pa[$i];
    
    # Encoded-normalize component
    $c = encNormName($c);
    
    # Make sure not "." or ".."
    (($c ne '.') and ($c ne '..')) or die "Invalid path, stopped";
    
    # If not last component or if directory flag is set, check that
    # normalization is not "index.i"
    if (($i < $#pa) or ($dir_flag)) {
      ($c ne 'index.i') or die "Invalid path normalization, stopped";
    }
    
    # Update component in array
    $pa[$i] = $c;
  }
  
  # Return the rejoined path
  return join '/', @pa;
}

# Given a Bitsy-encoded URL path to a file and a reference to a virtual
# file system hash, figure out what directory entries (if any) need to
# be added to the virtual file system and check that no conflicting
# files or directories already exist in the virtual file system.
#
# The given virtual file system reference must reference a hash with the
# same structure defined for the "vfs" property of Pack objects in the
# new() constructor.
#
# The provided Bitsy-encoded URL path is first encoded-normalized using
# encNormPath(), with faults occuring if there are any troubles.  The
# function checks that nothing currently exists for that normalized
# value in the hash, faulting otherwise.  This verifies that the full
# path does not already belong to an existing file or directory.
#
# Next, the encoded-normalized path is split into a sequence of one or
# more labels separated by forward slashes.  If there is only one label,
# then the path is to a file in the root directory of the website and
# just return an empty list in that case.
#
# Otherwise, iterate through directories in the encoded-normalized
# directory trail (defined in the Labrador spec), starting with the
# top-most directory and proceeding to the innermost directory, counting
# the number of trail elements that already exist as directories in the
# virtual file system.  If you encounter any elements in the directory
# trail that reference an existing file in the virtual file system, then
# a fault occurs.  If you encounter an element in the directory trail
# that does not exist in the virtual file system, then stop the loop
# without increasing the count of existing directories.  Otherwise,
# continue iterating and increasing the count.
#
# Go back to the original string argument (before encoding normalization
# was applied), and split that into a sequence of labels using "/" as a
# separator.  Generate a directory trail for this new sequence, but skip
# the first (n) elements of the directory trail, where (n) is the number
# of already existing directories determined in the previous step.  The
# result is the list of new directories that need to be added to the
# virtual file system.
#
# Parameters:
#
#   1 : string - the Bitsy-encoded URL path to a new file
#
#   2 : hash ref - the virtual file system reference
#
# Return:
#
#   an array of zero or more strings in list context containing the
#   Bitsy-encoded URL paths to directories that need to be added
#   (excluding trailing slashes for each path)
#
sub findDirs {
  
  # Check number of parameters
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $arg_path = shift;
  my $vfs      = shift;
  
  (not ref($arg_path)) or die "Wrong parameter type, stopped";
  $arg_path = "$arg_path";
  
  (ref($vfs) eq 'HASH') or die "Wrong parameter type, stopped";
  
  # Get the encoded-normalized path
  my $norm_path = encNormPath($arg_path, 0);
  
  # Check that normalized path doesn't already exist
  (not exists $vfs->{$norm_path}) or
    die "Path already exists in vfs: '$arg_path', stopped";
  
  # If the normalized path doesn't have any slashes, then there are no
  # directories and we can just return an empty list
  if (not ($norm_path =~ /\//)) {
    return ();
  }
  
  # If we got here there is at least one slash, so split the normalized
  # path AND the original path into arrays of components
  my @pa = split /\//, $norm_path;
  my @po = split /\//, $arg_path;
  
  # Both split arrays should have same number of elements
  ($#pa == $#po) or die "Unexpected";
  
  # Within the directory trail for the normalized path, count how many
  # elements of the directory trail already exist
  my $dir_count = 0;
  for(my $i = 0; $i <= ($#pa - 1); $i++) {
    # Get the current directory trail path
    my $d = join '/', @pa[0 .. $i];
    
    # Check whether directory entry exists
    if (exists $vfs->{$d}) {
      # Entry exists, so check whether it is for a directory
      if (not ref($vfs->{$d})) {
        # Entry is for a directory, so just increment the directory
        # count and continue iterating
        $dir_count++;
        
      } else {
        # Entry is for a file
        die "Directory/file conflict in vfs: '$d', stopped";
      }
      
    } else {
      # Directory entry does not exist, so leave loop without
      # incrementing directory count
      last;
    }
  }
  
  # Compute the result
  my @result;
  for(my $i = $dir_count; $i <= ($#pa - 1); $i++) {
    push @result, (join '/', @po[0 .. $i]);
  }
  
  # Return the result
  return @result;
}

# Given a Unicode URL string, encode it properly with Bitsy and check
# that it is valid.
#
# The given string must be non-empty and begin with a forward slash.
# However, it must not end with a forward slash character, and no
# forward slash character may be followed immediately with another
# forward slash character.  No path component may be "." or ".."  When
# encoded into Bitsy during this function, the encoded length may not
# exceed 1,023 characters.
#
# This function can't be used to directly encode URLs to index pages.
# Any path components that begin with index. after encoding will be
# escaped in the Bitsy encoding so that they do not get interpreted as
# index pages.
#
# The returned encoded URL does NOT begin with a forward slash.
#
# Parameters:
#
#   1 : string - the Unicode path to encode
#
# Return:
#
#   the Bitsy-encoded URL path
#
sub encodeURL {
  
  # Check parameter count
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $str = shift;
  
  (not ref($str)) or die "Wrong parameter type, stopped";
  $str = "$str";
  
  # Check that non-empty and begins with forward slash
  ($str =~ /^\//) or die "Invalid URL, stopped";
  
  # Check that last character is not slash and that no slash is followed
  # immediately by another slash
  ((not ($str =~ /\/$/)) and (not ($str =~ /\/\//))) or
    die "Invalid URL, stopped";
  
  # If we got here we know the string has at least two characters
  # because it starts with slash but doesn't end with slash; drop the
  # opening slash
  $str = substr $str, 1;
  
  # Parse into a sequence of components
  my @pa;
  if ($str =~ /\//) {
    @pa = split /\//, $str;
  } else {
    push @pa, ($str);
  }
  
  # Check and transform each component
  for my $d (@pa) {
    # Check that neither . nor ..
    (($d ne '.') and ($d ne '..')) or die "Invalid URL, stopped";
    
    # Bitsy-encode component
    $d = encodeBitsy($d);
    
    # If the encoded component begins with index. then escape it
    if ($d =~ /^index\.(.+)$/) {
      $d = 'xq--index-x.' . $1;
    }
  }
  
  # Rejoin to get the transformed path
  $str = join '/', @pa;
  
  # Check length constraint
  (length($str) <= $MAX_ZPATH) or die "Encode URL is too long, stopped";
  
  # Return encoded URL
  return $str;
}

# Given a Unicode URL string to a directory and a file extension, encode
# it properly with Bitsy and produce a file URL to an index file with
# the given index in the given directory and check that it is valid.
#
# The given path string must be non-empty and begin with a forward slash
# and end with a forward slash.  It may be a one-character string
# containing only a forward slash.  However, no forward slash character
# may be followed immediately with another forward slash character.  No
# path component may be "." or ".."  When encoded into Bitsy during this
# function, the encoded length may not exceed 1,023 characters.
#
# The given file extension will be converted to lowercase by this
# function.  When "a." is prefixed to it, it must be a valid StrictName
# according to Bitsy.
#
# The returned encoded URL does NOT begin with a forward slash.  The
# returned URL always ends with an encoded file name that begins with
# index. followed by the file extension that was provided.
#
# Parameters:
#
#   1 : string - the Unicode path to directory
#
#   2 : string - the file extension for the index page
#
# Return:
#
#   the Bitsy-encoded URL path to the index file
#
sub encodeIndexURL {
  
  # Check parameter count
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $dir_path = shift;
  my $file_ext = shift;
  
  (not ref($dir_path)) or die "Wrong parameter type, stopped";
  $dir_path = "$dir_path";
  
  (not ref($file_ext)) or die "Wrong parameter type, stopped";
  $file_ext = "$file_ext";
  
  # Make file extension lowercase and check it
  $file_ext =~ tr/A-Z/a-z/;
  (isStrictName('a.' . $file_ext)) or
    die "Invalid file extension, stopped";
  
  # Check that directory path begins and ends with a slash
  (($dir_path =~ /^\//) and ($dir_path =~ /\/$/)) or
    die "Invalid directory URL, stopped";
  
  # Suffix a dummy name "a" to the directory path and then encode this
  # URL
  my $url = encodeURL($dir_path . 'a');
  
  # Drop the last character from the encoded URL so we have just the
  # prefix before the dummy file name (which might be empty)
  $url = substr $url, 0, -1;
  
  # Suffix the index page with the proper extension
  $url = $url . 'index.' . $file_ext;
  
  # Check length constraint
  (length($url) <= $MAX_ZPATH) or die "Encode URL is too long, stopped";
  
  # Return the result
  return $url;
}

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
  # Each key is an encoded-normalized path to a file or a folder, with
  # folder paths NOT ending in a trailing slash.  Specifically, a key is
  # a sequence of one or more labels, where every label after the first
  # is preceded by a forward slash.  All labels except the last are
  # directory names that have been encoded-normalized.  The last label
  # is either a file name or a directory name, both of which must also
  # be encoded-normalized.  No label may be "." or ".." and no directory
  # label in encoded-normalized form may be "index.i"
  # 
  # Before adding a key to the "vfs" hash, you must make sure that keys
  # for each directory in the directory trail already exist, and that
  # all such keys are for folders.
  #
  # Keys for folders map to a string value containing the Bitsy-encoded
  # path to the folder, NOT including a trailing slash.  The total
  # length in characters of this folder path must not exceed MAX_ZPATH,
  # and the encoded-normalization of the folder path must be equal to
  # the key for the folder.
  #
  # Keys for files always map to a hash reference that represents the
  # file object.  The hash reference always has the following property:
  #
  #   - url : the encoded URL path to the file
  # 
  # The total length in characters of this property may not exceed
  # MAX_ZPATH, and the encoded-normalization of this URL path must be
  # equal to the key for this file.
  #
  # File objects that are being packed from a file in the local file
  # system will have the following additional properties:
  #
  #   - src : the path to the source file in the local file system
  #   - cmp : 1 to pack with compression, 0 for no compression
  #
  # File objects that are being packed from a string will have the
  # following additional property:
  #
  #   - txt : string containing raw octets of data
  # 
  # File objects that are being added with the sparse method will have
  # the following additional property:
  #
  #   - dig : the SHA-256 digest as a string of base-16 characters
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
Bitsy-encoded and does B<not> use any sort of percent encoding.  You may
use Unicode in the passed url string.  The url string must be non-empty
and begin with a forward slash.  However, it must not end with a forward
slash character, and no forward slash character may be followed
immediately with another forward slash character.  No path component may
be "." or ".."  When encoded into Bitsy during this function, the
encoded length may not exceed 1,023 characters.

The given url must not already exist in the website.  Also, for any
parent and ancestor folders containing the file specified in the URL,
the folder path must either already exist in the website as a folder or
not exist at all.  If any folder paths already exist as a file, a fault
will occur.

This function can not be used to add index pages.  If you give a url
that has a file name starting with index. then this function will escape
it in the Bitsy encoding so that it doesn't get interpreted as an index
page.  Similarly, any directory names in the path that begin with index.
will be escaped, since directories may never be indices.

The current state of the MIME type mappings has no bearing whatsoever
when this function is called.  The only thing that matters is the state
of the MIME type mappings when the compile function is eventually
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

Files added with this function may still end up sparse in the generated
archive if they are empty or if there are duplicate files and this file
is not the primary copy, as explained in the Labrador spec.  This is
determined when the compile function is called.

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
  
  # Make sure path references an existing file
  (-f $path) or die "Can't find file '$path', stopped";
  
  # Encode the URL
  $url = encodeURL($url);
  
  # Figure out the directories that need to be added, and check at the
  # same time that we are able to add this URL into our virtual file
  # system
  my @nda = findDirs($url, $self->{'vfs'});
  
  # Add all new directories
  for my $d (@nda) {
    $self->{'vfs'}->{encNormPath($d, 1)} = $d;
  }
  
  # Add the file object
  $self->{'vfs'}->{encNormPath($url, 0)} = {
    'url' => $url,
    'src' => $path,
    'cmp' => $compress
  };
}

=item B<object->packString(url, data)>

Register a raw data string that will be packed into the Labrador
archive.

data is a string containing the octets that will be added to this file.
All numeric character codes must be in range [0, 255].  If you are
adding a text string, be sure to encode it first.

url is a string that gives the URL that this file should be associated
with in the archived website.  The passed URL must B<not> be
Bitsy-encoded and does B<not> use any sort of percent encoding.  You may
use Unicode in the passed url string.  The url string must be non-empty
and begin with a forward slash.  However, it must not end with a forward
slash character, and no forward slash character may be followed
immediately with another forward slash character.  No path component may
be "." or ".."  When encoded into Bitsy during this function, the
encoded length may not exceed 1,023 characters.

The given url must not already exist in the website.  Also, for any
parent and ancestor folders containing the file specified in the URL,
the folder path must either already exist in the website as a folder or
not exist at all.  If any folder paths already exist as a file, a fault
will occur.

This function can not be used to add index pages.  If you give a url
that has a file name starting with index. then this function will escape
it in the Bitsy encoding so that it doesn't get interpreted as an index
page.  Similarly, any directory names in the path that begin with index.
will be escaped, since directories may never be indices.

The current state of the MIME type mappings has no bearing whatsoever
when this function is called.  The only thing that matters is the state
of the MIME type mappings when the compile function is eventually
called.

Files added with this function may still end up sparse in the generated
archive if they are empty or if there are duplicate files and this file
is not the primary copy, as explained in the Labrador spec.  This is
determined when the compile function is called.

=cut

sub packString {
  
  # Check parameter count
  ($#_ == 2) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self = shift;
  my $url  = shift;
  my $data = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($url)) or die "Wrong parameter type, stopped";
  $url = "$url";
  
  (not ref($data)) or die "Wrong parameter type, stopped";
  $data = "$data";
  
  # Make sure data includes only octets
  ($data =~ /^[\x{0}-\x{ff}]*$/) or
    die "String data must be raw octets, stopped";
  
  # Encode the URL
  $url = encodeURL($url);
  
  # Figure out the directories that need to be added, and check at the
  # same time that we are able to add this URL into our virtual file
  # system
  my @nda = findDirs($url, $self->{'vfs'});
  
  # Add all new directories
  for my $d (@nda) {
    $self->{'vfs'}->{encNormPath($d, 1)} = $d;
  }
  
  # Add the file object
  $self->{'vfs'}->{encNormPath($url, 0)} = {
    'url' => $url,
    'txt' => $data
  };
}

=item B<object->sparseDigest(url, sha256)>

Register a SHA-256 digest for a file that will be added into the
Labrador archive with the sparse method.

sha256 is the SHA-256 digest as a string containing a sequence of
exactly 64 base-16 characters.  This function will automatically convert
the string to lowercase.

url is a string that gives the URL that this file should be associated
with in the archived website.  The passed URL must B<not> be
Bitsy-encoded and does B<not> use any sort of percent encoding.  You may
use Unicode in the passed url string.  The url string must be non-empty
and begin with a forward slash.  However, it must not end with a forward
slash character, and no forward slash character may be followed
immediately with another forward slash character.  No path component may
be "." or ".."  When encoded into Bitsy during this function, the
encoded length may not exceed 1,023 characters.

The given url must not already exist in the website.  Also, for any
parent and ancestor folders containing the file specified in the URL,
the folder path must either already exist in the website as a folder or
not exist at all.  If any folder paths already exist as a file, a fault
will occur.

This function can not be used to add index pages.  If you give a url
that has a file name starting with index. then this function will escape
it in the Bitsy encoding so that it doesn't get interpreted as an index
page.  Similarly, any directory names in the path that begin with index.
will be escaped, since directories may never be indices.

The current state of the MIME type mappings has no bearing whatsoever
when this function is called.  The only thing that matters is the state
of the MIME type mappings when the compile function is eventually
called.

=cut

sub sparseDigest {
  
  # Check parameter count
  ($#_ == 2) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self = shift;
  my $url  = shift;
  my $sha  = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($url)) or die "Wrong parameter type, stopped";
  $url = "$url";
  
  (not ref($sha)) or die "Wrong parameter type, stopped";
  $sha = "$sha";
  
  # Make digest lowercase and check format
  $sha =~ tr/A-Z/a-z/;
  ($sha =~ /^[0-9a-f]{64}$/) or die "Invalid SHA-256 digest, stopped";
  
  # Encode the URL
  $url = encodeURL($url);
  
  # Figure out the directories that need to be added, and check at the
  # same time that we are able to add this URL into our virtual file
  # system
  my @nda = findDirs($url, $self->{'vfs'});
  
  # Add all new directories
  for my $d (@nda) {
    $self->{'vfs'}->{encNormPath($d, 1)} = $d;
  }
  
  # Add the file object
  $self->{'vfs'}->{encNormPath($url, 0)} = {
    'url' => $url,
    'dig' => $sha
  };
}

=item B<object->packIndexFile(url, ext, path, compress)>

Register an index file that will be packed into the Labrador archive.

This function does not actually read the file yet.  Instead, it simply
records the registration internally in the object.  The file will
actually be read and packed when the compile function is called.

url is a string that gives the URL of the directory that this index file
should be associated with in the archived website.  The passed URL must
B<not> be Bitsy-encoded and does B<not> use any sort of percent
encoding.  You may use Unicode in the passed url string.  The url string
must be non-empty, begin with a forward slash, and end with a forward
slash (an url consisting of just a forward slash is OK).  However, no
forward slash character may be followed immediately with another forward
slash character.  No path component may be "." or ".."  When encoded
into Bitsy during this function, the encoded length may not exceed 1,023
characters.

No index file may already exist in the website for the given directory,
even if the other index file has a different extension.  Also, the given
directory and all parent and ancestor folders must either already exist
in the website as a folder or not exist at all.  If any folder paths
already exist as a file, a fault will occur.

This function will automatically add the appropriate Bitsy-encoded index
file name to the end of the encoded URL, followed by the extension given
by the ext parameter.  This extension must be a StrictName according to
Bitsy if 'a.' is prefixed to it.  However, any directory names in the
given path that begin with index. will be escaped in the Bitsy encoding,
since directories may never be indices.

The current state of the MIME type mappings has no bearing whatsoever
when this function is called.  The only thing that matters is the state
of the MIME type mappings when the compile function is eventually
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

Files added with this function may still end up sparse in the generated
archive if they are empty or if there are duplicate files and this file
is not the primary copy, as explained in the Labrador spec.  This is
determined when the compile function is called.

=cut

sub packIndexFile {
  
  # Check parameter count
  ($#_ == 4) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self     = shift;
  my $url      = shift;
  my $ext      = shift;
  my $path     = shift;
  my $compress = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($url)) or die "Wrong parameter type, stopped";
  $url = "$url";
  
  (not ref($ext)) or die "Wrong parameter type, stopped";
  $ext = "$ext";
  
  (not ref($path)) or die "Wrong parameter type, stopped";
  $path = "$path";
  
  (not ref($compress)) or die "Wrong parameter type, stopped";
  (int($compress) == $compress) or die "Wrong parameter type, stopped";
  $compress = int($compress);
  (($compress == 0) or ($compress == 1)) or
    die "Wrong parameter type, stopped";
  
  # Make sure path references an existing file
  (-f $path) or die "Can't find file '$path', stopped";
  
  # Encode the index URL
  $url = encodeIndexURL($url, $ext);
  
  # Figure out the directories that need to be added, and check at the
  # same time that we are able to add this URL into our virtual file
  # system
  my @nda = findDirs($url, $self->{'vfs'});
  
  # Add all new directories
  for my $d (@nda) {
    $self->{'vfs'}->{encNormPath($d, 1)} = $d;
  }
  
  # Add the file object
  $self->{'vfs'}->{encNormPath($url, 0)} = {
    'url' => $url,
    'src' => $path,
    'cmp' => $compress
  };
}

=item B<object->packIndexString(url, ext, data)>

Register a raw data string that will be packed into the Labrador
archive as an index file.

data is a string containing the octets that will be added to this file.
All numeric character codes must be in range [0, 255].  If you are
adding a text string, be sure to encode it first.

url is a string that gives the URL of the directory that this index file
should be associated with in the archived website.  The passed URL must
B<not> be Bitsy-encoded and does B<not> use any sort of percent
encoding.  You may use Unicode in the passed url string.  The url string
must be non-empty, begin with a forward slash, and end with a forward
slash (an url consisting of just a forward slash is OK).  However, no
forward slash character may be followed immediately with another forward
slash character.  No path component may be "." or ".."  When encoded
into Bitsy during this function, the encoded length may not exceed 1,023
characters.

No index file may already exist in the website for the given directory,
even if the other index file has a different extension.  Also, the given
directory and all parent and ancestor folders must either already exist
in the website as a folder or not exist at all.  If any folder paths
already exist as a file, a fault will occur.

This function will automatically add the appropriate Bitsy-encoded index
file name to the end of the encoded URL, followed by the extension given
by the ext parameter.  This extension must be a StrictName according to
Bitsy if 'a.' is prefixed to it.  However, any directory names in the
given path that begin with index. will be escaped in the Bitsy encoding,
since directories may never be indices.

The current state of the MIME type mappings has no bearing whatsoever
when this function is called.  The only thing that matters is the state
of the MIME type mappings when the compile function is eventually
called.

Files added with this function may still end up sparse in the generated
archive if they are empty or if there are duplicate files and this file
is not the primary copy, as explained in the Labrador spec.  This is
determined when the compile function is called.

=cut

sub packIndexString {
  
  # Check parameter count
  ($#_ == 3) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self = shift;
  my $url  = shift;
  my $ext  = shift;
  my $data = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($url)) or die "Wrong parameter type, stopped";
  $url = "$url";
  
  (not ref($ext)) or die "Wrong parameter type, stopped";
  $ext = "$ext";
  
  (not ref($data)) or die "Wrong parameter type, stopped";
  $data = "$data";
  
  # Make sure data includes only octets
  ($data =~ /^[\x{0}-\x{ff}]*$/) or
    die "String data must be raw octets, stopped";
  
  # Encode the URL
  $url = encodeIndexURL($url, $ext);
  
  # Figure out the directories that need to be added, and check at the
  # same time that we are able to add this URL into our virtual file
  # system
  my @nda = findDirs($url, $self->{'vfs'});
  
  # Add all new directories
  for my $d (@nda) {
    $self->{'vfs'}->{encNormPath($d, 1)} = $d;
  }
  
  # Add the file object
  $self->{'vfs'}->{encNormPath($url, 0)} = {
    'url' => $url,
    'txt' => $data
  };
}

=item B<object->sparseIndexDigest(url, ext, sha256)>

Register a SHA-256 digest for an index file that will be added into the
Labrador archive with the sparse method.

sha256 is the SHA-256 digest as a string containing a sequence of
exactly 64 base-16 characters.  This function will automatically convert
the string to lowercase.

url is a string that gives the URL of the directory that this index file
should be associated with in the archived website.  The passed URL must
B<not> be Bitsy-encoded and does B<not> use any sort of percent
encoding.  You may use Unicode in the passed url string.  The url string
must be non-empty, begin with a forward slash, and end with a forward
slash (an url consisting of just a forward slash is OK).  However, no
forward slash character may be followed immediately with another forward
slash character.  No path component may be "." or ".."  When encoded
into Bitsy during this function, the encoded length may not exceed 1,023
characters.

No index file may already exist in the website for the given directory,
even if the other index file has a different extension.  Also, the given
directory and all parent and ancestor folders must either already exist
in the website as a folder or not exist at all.  If any folder paths
already exist as a file, a fault will occur.

This function will automatically add the appropriate Bitsy-encoded index
file name to the end of the encoded URL, followed by the extension given
by the ext parameter.  This extension must be a StrictName according to
Bitsy if 'a.' is prefixed to it.  However, any directory names in the
given path that begin with index. will be escaped in the Bitsy encoding,
since directories may never be indices.

The current state of the MIME type mappings has no bearing whatsoever
when this function is called.  The only thing that matters is the state
of the MIME type mappings when the compile function is eventually
called.

=cut

sub sparseIndexDigest {
  
  # Check parameter count
  ($#_ == 3) or die "Wrong number of parameters, stopped";
  
  # Get parameters and check types
  my $self = shift;
  my $url  = shift;
  my $ext  = shift;
  my $sha  = shift;
  
  (ref($self)) or die "Wrong self type, stopped";
  ($self->isa(__PACKAGE__)) or die "Wrong self type, stopped";
  
  (not ref($url)) or die "Wrong parameter type, stopped";
  $url = "$url";
  
  (not ref($ext)) or die "Wrong parameter type, stopped";
  $ext = "$ext";
  
  (not ref($sha)) or die "Wrong parameter type, stopped";
  $sha = "$sha";
  
  # Make digest lowercase and check format
  $sha =~ tr/A-Z/a-z/;
  ($sha =~ /^[0-9a-f]{64}$/) or die "Invalid SHA-256 digest, stopped";
  
  # Encode the URL
  $url = encodeIndexURL($url, $ext);
  
  # Figure out the directories that need to be added, and check at the
  # same time that we are able to add this URL into our virtual file
  # system
  my @nda = findDirs($url, $self->{'vfs'});
  
  # Add all new directories
  for my $d (@nda) {
    $self->{'vfs'}->{encNormPath($d, 1)} = $d;
  }
  
  # Add the file object
  $self->{'vfs'}->{encNormPath($url, 0)} = {
    'url' => $url,
    'dig' => $sha
  };
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
