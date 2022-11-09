{ lib }:
let
  inherit (lib) filter concatMap concatStringsSep hasPrefix head
    replaceStrings removePrefix foldl' elem;
  inherit (lib.strings) sanitizeDerivationName;
  inherit (lib.types) coercedTo str;

  # ["/home/user/" "/.screenrc"] -> ["home" "user" ".screenrc"]
  splitPath = paths:
    filter builtins.isString (builtins.split "/" (concatPaths paths));

  # Remove duplicate "/" elements, "/./", "foo/..", etc., from a path
  cleanPath = path:
    let
      dummy = builtins.placeholder path;
      prefix = "${dummy}/";
      expanded = toString (/. + "${prefix}${path}");
    in
    if lib.hasPrefix "/" path then
      toString (/. + path)
    else if expanded == dummy then
      "."
    else if lib.hasPrefix prefix expanded then
      removePrefix prefix expanded
    else
      throw "illegal path traversal in `${path}`";

  # ["home" "user" ".screenrc"] -> "home/user/.screenrc"
  # ["/home/user/" "/.screenrc"] -> "/home/user/.screenrc"
  dirListToPath = dirList: cleanPath (concatStringsSep "/" dirList);

  # Alias of dirListToPath
  concatPaths = dirListToPath;

  sanitizeName = name:
    replaceStrings
      [ "." ] [ "" ]
      (sanitizeDerivationName (removePrefix "/" name));

  duplicates = list:
    let
      result =
        foldl'
          (state: item:
            if elem item state.items then
              {
                items = state.items ++ [ item ];
                duplicates = state.duplicates ++ [ item ];
              }
            else
              state // {
                items = state.items ++ [ item ];
              })
          { items = [ ]; duplicates = [ ]; }
          list;
    in
    result.duplicates;

  coercedToDir = coercedTo str (directory: { inherit directory; });
  coercedToFile = coercedTo str (file: { inherit file; });
in
{
  inherit splitPath cleanPath dirListToPath concatPaths sanitizeName
    duplicates coercedToDir coercedToFile;
}
