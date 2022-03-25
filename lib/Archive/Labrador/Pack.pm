package Archive::Labrador::Pack;
use strict;

=head1 NAME

Archive::Labrador::Pack - Build new Labrador archives by packing files.

=head1 SYNOPSIS

  use Archive::Labrador::Pack;
  
  # Create a new pack object
  my $pack = Archive::Labrador::Pack->new();
  
  # Define MIME type mappings
  $pack->mapType('.jpg', 'image/jpeg');
  $pack->mapType('.png', 'image/png');
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
