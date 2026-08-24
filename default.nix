/*
  A small, project-agnostic library for reading `variables:` blocks out of
  YAML files (GitLab CI templates, plain YAML, ...) and turning them into a
  flat attrset of strings suitable for `env`.

  Variable blocks must be mappings (`name: value`); list-style entries such as
  docker-compose's `- NAME=value` environment lists are not supported.

  It makes no assumptions about file layout: every path is passed in by the
  caller.

  Usage:
    yamlVars = inputs.nix-yaml-vars.lib { inherit pkgs; };

    # simplest form: merge the `variables:` blocks of several files,
    # then expand $FOO / ${FOO} references
    vars = yamlVars.load {
      files = [ ./ci/templates/base.yml (./ci/env + "/dev-eu.yml") ];
      extra = { AWS_ACCOUNT_ID = "1234567890"; };
    };

    # other entry points
    yamlVars.fromYAML ./anything.yml          # YAML file  -> attrset
    yamlVars.varsOf ./ci/templates/base.yml   # `variables:` of one file
    yamlVars.varsAt [ "x" "env" ] ./f.yml     # `variables:` at a custom path
    yamlVars.expand { A = "$B"; B = "1"; }    # reference expansion only

  Note: this uses import-from-derivation (yq-go converts YAML -> JSON at eval
  time), which devenv/nix allows by default.
*/
{
  pkgs,
  lib,
  # name of the attribute holding the variable block; may also be a list of
  # attribute names for nested locations (e.g. [ "x" "variables" ]).
  defaultAttrPath ? [ "variables" ],
  # fail on references to undefined variables instead of expanding them to ""
  defaultStrict ? true,
}:

let
  toPath = p: if builtins.isList p then p else [ p ];

  # Derive a usable derivation name from an arbitrary path or string.
  nameOf =
    path:
    let
      base = baseNameOf (toString path);
      stripped = lib.removeSuffix ".yaml" (lib.removeSuffix ".yml" base);
      # sanitizeDerivationName handles every store-illegal character
      # (spaces, ':', '#', '?', leading '.', ...), not just spaces.
      cleaned = lib.strings.sanitizeDerivationName stripped;
    in
    if stripped == "" || cleaned == "unknown" then "yaml" else cleaned;

  # YAML file -> Nix attrset (IFD)
  fromYAML' =
    name: path:
    let
      json = pkgs.runCommand "${name}.json" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
        yq -o=json '.' ${lib.escapeShellArg "${path}"} > $out
      '';
    in
    builtins.fromJSON (builtins.readFile json);

  fromYAML = path: fromYAML' (nameOf path) path;

  # `variables:` (or any other attr path) of a YAML file, {} if absent.
  varsAt =
    attrPath: path:
    let
      get =
        attrs: keys:
        if keys == [ ] then
          attrs
        else if builtins.isAttrs attrs && builtins.hasAttr (lib.head keys) attrs then
          get attrs.${lib.head keys} (lib.tail keys)
        else
          { };
    in
    get (fromYAML path) (toPath attrPath);

  varsOf = varsAt defaultAttrPath;

  # Expand ${FOO} / $FOO references against an attrset. Values may reference
  # other values; each reference is resolved recursively, so definition order
  # does not matter. In strict mode an unknown name is an eval error, otherwise
  # it expands to "". A reference cycle is an eval error, detected as soon as a
  # name refers back to itself.
  expandWith =
    strict: vars:
    let
      v = lib.mapAttrs (_: toStr) vars;

      # `stack` is the chain of names currently being resolved.
      expandStr =
        stack: s:
        builtins.concatStringsSep "" (
          map (
            part:
            if builtins.isList part then resolve stack (lib.head (lib.filter (x: x != null) part)) else part
          ) (builtins.split "[$][{]([A-Za-z_][A-Za-z0-9_]*)[}]|[$]([A-Za-z_][A-Za-z0-9_]*)" s)
        );

      resolve =
        stack: name:
        if builtins.elem name stack then
          throw ''
            nix-yaml-vars: circular $VAR reference: ${lib.concatStringsSep " -> " (stack ++ [ name ])}
          ''
        else if v ? ${name} then
          expandStr (stack ++ [ name ]) v.${name}
        else if strict then
          throw ''
            nix-yaml-vars: undefined variable ''$${name}, referenced from ${lib.concatStringsSep " -> " stack}
          ''
        else
          "";
    in
    lib.mapAttrs (k: s: expandStr [ k ] s) v;

  expand = expandWith defaultStrict;

  toStr =
    v:
    if builtins.isBool v then
      (if v then "true" else "false")
    else if builtins.isInt v || builtins.isFloat v then
      toString v
    else if builtins.isString v then
      v
    else if v == null then
      ""
    else
      # numbers/paths/derivations and anything else with a sane string form
      toString v;
in
rec {
  inherit
    fromYAML
    varsAt
    varsOf
    expand
    expandWith
    toStr
    ;

  # Merge the variable blocks of several YAML files (later files win).
  mergeFiles =
    {
      files,
      attrPath ? defaultAttrPath,
    }:
    lib.foldl' (acc: f: acc // lib.mapAttrs (_: toStr) (varsAt attrPath f)) { } files;

  /*
    Main entry point.

    files      : list of YAML files to read, later ones override earlier ones
    extra      : attrset merged last, for values only known outside of CI
    attrPath   : where the variables live inside each file
    keepEmpty  : keep variables that expand to "" (default: drop them)
    expandRefs : perform $VAR expansion (default: true)
    strict     : fail on references to undefined variables (default: true)
  */
  load =
    {
      files ? [ ],
      extra ? { },
      attrPath ? defaultAttrPath,
      keepEmpty ? false,
      expandRefs ? true,
      strict ? defaultStrict,
    }:
    let
      raw = mergeFiles { inherit files attrPath; } // lib.mapAttrs (_: toStr) extra;
      expanded = if expandRefs then expandWith strict raw else raw;
    in
    if keepEmpty then expanded else lib.filterAttrs (_: v: v != "") expanded;
}
