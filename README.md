# Labrador archive format

Labrador is an archive format for a whole website.  Labrador supports archives of static websites and also web apps that are entirely client-side.  Labrador also supports websites that use Unicode in their file paths without requiring Unicode support in the underlying Zip archive.  However, Labrador does not support websites that require server-side scripting.

## Header file

Labrador is based on the Zip archive format.  Following a common convention, the first file stored within this Zip archive must be an uncompressed file named `mimetype` that stores the Labrador MIME type as a case-sensitive US-ASCII string with no whitespace.  The Labrador MIME type is:

    application/x-labrador

## Key/value file format

Labrador also contains special data files in a _key/value format_ described in this section.

Key/value data files are US-ASCII plain-text files.  Only printing US-ASCII characters in range [U+0020, U+007E] may be present within lines.  Each line except the last ends with either LF (U+000A) or with the sequence CR+LF (U+000D U+000A).  The last line ends at the End Of File (EOF).

Each line of a key/value file is either empty or a record.  Empty lines contain a sequence of zero or more space characters (U+0020) followed by the line break or EOF.  Empty lines are ignored.

Record lines have the following format:

1. Optional space
2. Key sequence
3. Required space
4. Value sequence
5. Optional space
6. Line break or EOF

_Optional space_ means a sequence of zero or more space characters (U+0020), while _required space_ means a sequence of one or more space characters.

_Key sequence_ is a sequence of one or more printing, non-space characters in range [U+0021, U+007E].

_Value sequence_ is a sequence of one or more printing characters in range [U+0020, U+007E], with the restriction that neither the first nor last character of the value sequence may be a space (U+0020).  Space characters may be used internally, however.

Each record line in a key/value data file represents a data record with a _key_ field being a string equivalent to the key sequence and the _value_ field being a string equivalent to the value sequence.  The specific meaning of the key and value fields depends on the specific application of the key/value data file.  The order of record lines within a key/value data file does not matter.

## Type declarations file

The second file stored within the Zip archive must be a file named `extmime` that stores the mapping of file extensions to file types within the website files.  (This mapping does not apply to the `extmime` file itself, nor to the `mimetype` file defined above, nor to the `manifest` file defined below.)  This second file may optionally be compressed.

The `extmime` file must be in the key/value format described in the previous section.  Key fields represent file extensions without the leading dot and value fields represent the MIME type that should be transmitted to the HTTP client in the `Content-Type` header when resources with this file extension are selected.  For example:

    html text/html; charset=UTF-8
    htm  text/html; charset=UTF-8
    midi audio/midi
    png  image/png
    jpg  image/jpeg
    jpeg image/jpeg

Multiple file extensions may map to the same type.  In the above example, `html` and `htm` file extensions both map to `text/html; charset=UTF-8` and `jpg` and `jpeg` both map to `image/jpeg`.

File extensions are case-insensitive, so `example.png` and `example.PNG` and `example.Png` would all map to `image/png` according to the example given above.  File extensions given in the `extmime` file must be in lowercase AND when `a.` is prefixed to them they must be a StrictName according to the Bitsy specification.

Each file extension key defined in `extmime` must be unique.  If there are no type mappings to declare, the `extmime` file must still be present but it may be empty.

### Compound types

Periods may be used within file extensions in `extmime` for compound types such as `tar.gz`  When a period is used within any file extensions, ambiguity may arise.  For example:

    gz     application/gzip
    tar.gz application/x-tgz

If we have a file `example.tar.gz` then both the `gz` and `tar.gz` properties from the above example match it.  Labrador always uses the longest possible match to resolve these ambiguities.  Therefore, `example.tar.gz` would map to `application/x-tgz` with this example, while `beispiel.gz` would map to `application/gzip`

### Catch-all type

There is also a catch-all type that is used when none of the declared extensions in the `extmime` file match a particular file name.  By default, the catch-all type is `application/octet-stream` but you can change this default.

To explicitly set the catch-all type, you can use the special key `.` and map this to a string that is used as the catch-all type.  For example:

    . text/html

The above example will change the catch-all type to `text/html` and since no other types are defined, this will result in all files in the website being identified as `text/html`

### Blank type

If a file name _after being encoded in Bitsy_ does not contain any period characters, then it is a _blank type._  Note that Bitsy encoding may drop certain period characters from the original name, so even if the original name has period characters, it may still end up being a blank type.

By default, blank types are handled with the catch-all type defined in the previous section.  However, you may set an explicit blank type by using the special key `-` and mapping this to a string that is used as the blank type.  For example:

    .   application/octet-stream
    -   text/html
    png image/png

Using this example, the following shows some examples of how file names would be mapped to types:

    example     -> text/html (blank type)
    example.png -> image/png
    example.zwx -> application/octet-stream (catch-all type)

## Manifest file

The third file stored within the Zip archive must be a file named `manifest` that stores a snapshot of all website data stored within the archive (excluding the manifest file itself, the type declarations file, and the header file).  This third file may optionally be compressed.

The `manifest` file must be in the key/value format described earlier.  Key fields represent Bitsy-encoded URLs to files within the archived website, and value fields are SHA-256 digests of the file contents as a sequence of base-16 characters.  For example:

    example.html                         2cf24dba5...
    xz--bcher-nf5/xz--Rotfchse-jboqb.png 73ef70b68...

SHA-256 digests have been abbreviated in this example.  Valid SHA-256 digests must be a sequence of exactly 64 base-16 digit characters, each of which is either a decimal digit `0-9` or a letter `A-F` or `a-f`.

Key fields must be a sequence of zero or more directory names followed by a file name.  Each directory name must end with a forward slash.  The file name as well as each directory name excluding the slash must all be valid Bitsy-encoded strings.  No directory name nor the file name may be the special names `.` or `..`  No directory name may begin with a case-insensitive match for the six characters `index.` (including the dot at the end), but file names may begin this way.  The length of the whole key field must not exceed 1,023 characters.

Key fields may use both uppercase and lowercase letters, but they are case insensitive.  (The Bitsy-decoded original URL paths _are_ case sensitive, however.)  The key fields _after Bitsy decoding_ are equal to the URL path to the file in the archived website, relative to the root of the website, but without any percent encoding applied.

HTTP allows you to associate file data with directory names, but this is not allowed in Zip archives.  If the (Bitsy-encoded) key field begins with `index.` (note the dot at the end!) then the file will be returned for the parent URL directory and _not_ for that file name.  For example:

    index.html          -> www.example.com/
    my/subdir/index.txt -> www.example.com/my/subdir/

The MIME type will be determined for this index file using the usual matching algorithm on the Bitsy-encoded file name.  You are not allowed to use this special format of name for directory names.

Since this system requires a period to follow the `index` name and that there not be any `xq--` or `xz--` Bitsy prefixes, it is still acceptable to have files and directories named as `index` as well as any name that involves a Bitsy prefix:

    index/index      -> www.example.com/index/index
    xz--index-ec.txt -> www.example.com/index.TXT

If you really need a file named something like `index.html` that is not interpreted as a directory page, then use a Bitsy `xq--` escaping prefix with a `-x` suffix immediately before the extension like this:

    xq--index-x.html -> www.example.com/index.html

Note that `xq--index-x.html` is not the usual Bitsy encoding for `index.html` so if you want to do this, you will have to manually encode it that way yourself rather than using the Bitsy encoder.  The Bitsy decoder will still decode this name properly.

If there are no archived files in the website, the `manifest` file must still be present but should contain no record lines.

### Uniqueness

Define the _encoded normalization_ of a name as follows.  First, convert all uppercase letters to lowercase.  Second, in the special case of a lowercased name beginning with `xq--index-x.` (including the period at the end), let the encoded normalization be just the lowercased name and skip all subsequent normalization steps.  Otherwise, the third step is to check whether the name begins with `index.` (including the period at the end), and if it does change the name to `index.i` before proceeding.  The fourth step is to Bitsy-decode the name to Unicode.  Fifth and finally, Bitsy-encode the decoded Unicode name back to ASCII.  The result of this process is the encoded normalization of the name.

(Essentially, encoded normalization makes sure the encoded name is properly normalized under Unicode, and that the Bitsy encoding is the usual encoding, except in the special case of a lowercased name beginning with `xq--index-x.` which is a Labrador-specific escape for a file with a name beginning with `index.` that should _not_ be interpreted as a directory index file.  Also, true index files have their extensions all normalized to `.i`)

Define the encoded normalization of a path as the path when each of its component directory names and the file name are all transformed into their encoded normalization.

Define the _directory trail_ of a path as follows.  If there are no forward slashes in the path, then the directory trail is an empty array.  Otherwise, split the path into an array of two or more components using the forward slash as an element separator.  Let `n` be the total number of components that have been split out.  The directory trail then is an array of `(n - 1)` elements, where the first element `e_0` is split component zero (the first component) and element `e_(i + 1)` is `e_i` with a forward slash and then split component `(i + 1)` suffixed.  For example:

    example/path/to/file.txt
    
    Directory trail:
    example
    example/path
    example/path/to

Given these definitions, we can now formulate the uniqueness constraints for key fields in the manifest.

The __file uniqueness constraint__ says that the encoded normalization of each record's key field must be unique among the set of encoded normalizations of all record keys.  This ensures that each file path is unique when decoded to Unicode and also that there is no more than one index file per directory (since each index file during encoded normalization is transformed to have the same extension).

The __directory uniqueness constraint__ says that for each element in the directory trail of each record's key field, the encoded normalization of each such element must not exist among the set of encoded normalizations of all record keys.  This ensures that no path is used both as a file and a directory.

## Website tree

The archived website files are contained within a folder named `www` on the root level of the Zip archive.  Only files that have been recorded in the manifest file may be included in the website tree.  The path within the Zip archive to a data file is equal to the (Bitsy-encoded) path to the file within the manifest, with `www/` prefixed to the path.  File paths within Zip archives are case insensitive.

Not every file that appears in the manifest will also appear in the website tree.  The following subsections document the cases that cause a file to be suppressed from appearing in the website tree within the Zip archive.

The `www` directory is always present within the Zip archive, even if it is empty.  Further subdirectories are only defined if they are needed for a file that is being stored within the website tree.

### Empty file suppression

Files that are empty (contain zero bytes) are never stored within the website tree.  Instead, they are recognized by the following SHA-256 digest of an empty file within the manifest:

    e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

Any file that has a SHA-256 digest matching this value is an empty file containing zero bytes, and never appears within the website tree.

### Duplicate file suppression

If an archived website contains multiple exact copies of the same file at different URL locations, only one copy &mdash; the _primary_ copy &mdash; may be stored, and all secondary (non-primary) copies are always suppressed.  (The primary copy might also be suppressed if it falls in one of the other suppression cases.)

Given a set of two or more keys within the manifest that refer to the same SHA-256 digest, the following algorithm determines which key is the primary copy.

First, get the encoded normalization of each key, using the process described earlier.  Second, count the number of forward slashes in each key and let _m_ be the minimum of the set of all forward slash counts.  Drop all keys that have more than _m_ forward slashes.  Third, count the number of characters in each remaining key and let _n_ be the minimum of the set of all character counts.  Drop all keys that have more than _n_ characters.  Fourth, sort the remaining keys in lexicographic order by ASCII character codes.  The key with the lowest value in this order is the key corresponding to the primary copy, and all other keys are secondary copies.

### External file suppression

Any file from the manifest may be suppressed from appearing in the website tree.  If there are any suppressed files that do not fall into one of preceding two cases, then _external file suppression_ applies to the Labrador archive.  With the non-external file suppression cases, it is possible to reconstruct all data using just what is available within the Labrador archive, but the moment there is any external file suppression, the archive is incomplete without some external source to consult for the external suppressed files.

External file suppression is not generally a good idea for archival applications.  However, it can greatly boost efficiency when using Labrador as a transport format by allowing for incremental updates &mdash; file data that is already present in the receiver's current version can be suppressed, and the receiver can then use the old version to fill in the missing files from the current version.  External file suppression is also useful in image gallery applications and the like, where there is an external source (gallery) that can be consulted to find the missing files.
