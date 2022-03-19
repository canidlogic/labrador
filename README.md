# Labrador archive format

Labrador is an archive format for a whole website.  Labrador supports archives of static websites and also web apps that are entirely client-side.  Labrador also supports websites that use Unicode in their file paths without requiring Unicode support in the underlying Zip archive.  However, Labrador does not support websites that require server-side scripting.

## Header file

Labrador is based on the Zip archive format.  Following a common convention, the first file stored within this Zip archive must be an uncompressed file named `mimetype` that stores the Labrador MIME type as a case-sensitive US-ASCII string with no whitespace.  The Labrador MIME type is:

    application/x-labrador

## Type declarations file

The second file stored within the Zip archive must be a file named `mime.json` that stores the mapping of file extensions to file types within the website files.  (This mapping does not apply to the `mime.json` file itself, nor to the `mimetype` file defined above.)  This second file may optionally be compressed.

The `mime.json` file must be a JSON data file with a specific format.  The top-level entity in the JSON must be a JSON object.  The property names of this top-level JSON object are extension names without the leading dot and the property values of this top-level JSON object are strings that store the MIME type that should be transmitted to the HTTP client when resources of this extension are selected.  For example:

    {
      "html": "text/html",
      "htm": "text/html",
      "midi": "audio/midi",
      "png": "image/png",
      "jpg": "image/jpeg",
      "jpeg": "image/jpeg"
    }

Multiple file extensions may map to the same type.  In the above example, `html` and `htm` file extensions both map to `text/html` and `jpg` and `jpeg` both map to `image/jpeg`.

File extensions are case-insensitive, so `example.png` and `example.PNG` and `example.Png` would all map to `image/png` according to the example given above.  File extensions given in the `mime.json` file must be in lowercase AND when `a.` is prefixed to them they must be a StrictName according to the Bitsy specification.

### Compound types

Periods may be used within file extension property names for compound types such as `tar.gz`  When a period is used within any file extensions, ambiguity may arise.  For example:

    {
      "gz": "application/gzip",
      "tar.gz": "application/x-tgz"
    }

If we have a file `example.tar.gz` then both the `gz` and `tar.gz` properties from the above example could apply to it, yielding different results.  Labrador always uses the longest possible match to resolve these ambiguities.  Therefore, `example.tar.gz` would always map to `application/x-tgz` with this example, while `beispiel.gz` would map to `application/gzip`

### Catch-all type

There is also a catch-all type that is used when none of the declared extensions in the `mime.json` file match a particular file name.  By default, the catch-all type is `application/octet-stream` but you can change this default.

To explicitly set the catch-all type, you can use the special `.` property name and map this to a string that is used as the catch-all type.  For example:

    {
      ".": "text/html"
    }

The above example will change the catch-all type to `text/html` and since no other types are defined, this will result in all files in the website being labeled as `text/html`

### Blank type

If a file name _after being encoded in Bitsy_ does not contain any period characters, then it is a _blank type._  Note that Bitsy encoding may drop certain period characters from the original name, so even if the original name has period characters, it may still end up being a blank type.

By default, blank types are handled with the catch-all type defined in the previous section.  However, you may set an explicit blank type by using the special `-` property name and mapping this to a string that is used as the blank type.  For example:

    {
      ".": "application/octet-stream",
      "-": "text/html",
      "png": "image/png"
    }

Using this example, the following shows some examples of how file names would be mapped to types:

    example     -> text/html (blank type)
    example.png -> image/png
    example.zwx -> application/octet-stream (catch-all type)

## Website tree

The whole website archive is contained within a folder named `www` on the top level of the Zip archive.  Files that have `www` as their immediate parent folder will be located in the root directory of the website, while directories within `www` are subdirectories of the root directory of the website.

Supposing that a Labrador archive is representing the website at `www.example.com`, here is how files within the Labrador archive would map to URLs:

    www/hello.txt           -> www.example.com/hello.txt
    www/my/subdir/file.html -> www.example.com/my/subdir/file.html

HTTP allows you to store pages at directory names, while directories are not allowed to directly contain any file data in Zip files.  If a file has the special name `index` in the Zip archive then it does _not_ refer to a file named `index` in the URL mapping but rather to its parent directory:

    www/index           -> www.example.com/
    www/my/subdir/index -> www.example.com/my/subdir/

The MIME type used for `index` files will be the blank type if one is defined, and otherwise the catch-all type.

All file and directory names within the `www` folder of the Zip archive are encoded with Bitsy.  (The preceding examples still work, because all names used in the preceding examples use pass-through encoding in Bitsy.)  In the URL encoding, the decoded Bitsy original names will be used instead:

    www/xz--example-e6.txt                   -> www.example.com/example.TXT
    www/xz--example-im.txt                   -> www.example.com/Example.txt
    www/xz--bcher-nf5/xz--Rotfchse-jboqb.png -> www.example.com/bücher/Rotfüchse.png

Note from the above example that while the mapped URL names are case sensitive, the file names stored in the website archive are case insensitive.  File extension mapping is performed on the Bitsy-encoded file names, rather than their original string value.
