# nix-yaml-vars

[![CI](https://github.com/michaeladler/nix-yaml-vars/actions/workflows/ci.yml/badge.svg)](https://github.com/michaeladler/nix-yaml-vars/actions/workflows/ci.yml)

A small, project-agnostic Nix library for reading `variables:` blocks out of
YAML files (GitLab CI templates, docker-compose files, plain YAML, ...) and
turning them into a flat attrset of strings, e.g. for devenv's `env`.

## Usage

With [devenv](https://github.com/cachix/devenv), add to `devenv.yaml`:

```yaml
inputs:
  nix-yaml-vars:
    url: github:michaeladler/nix-yaml-vars
```

and use `inputs.nix-yaml-vars.lib` in `devenv.nix`:

```nix
{ pkgs, lib, inputs, ...}:

let
  yamlVars = inputs.nix-yaml-vars.lib { inherit pkgs lib; };
in
{
  # merge the `variables:` blocks of several files, then expand
  # $FOO / ${FOO} references
  env = yamlVars.load {
    # NOTE: later ones override earlier ones
    files = [ ./ci/env/base.yaml ./ci/env/dev.yaml ];
    # Extra values have highest priority and are also used for variable resolution
    extra = { AWS_ACCOUNT_ID = "1234567890"; };
  };
}
```

## API

| Entry point                                              | Description                                               |
|----------------------------------------------------------|-----------------------------------------------------------|
| `load { files, extra, attrPath, keepEmpty, expandRefs }` | Main entry point: merge, expand, filter.                  |
| `mergeFiles { files, attrPath }`                         | Merge variable blocks of several files (later files win). |
| `fromYAML ./anything.yml`                                | Whole YAML file -> attrset.                               |
| `varsOf ./ci/templates/base.yml`                         | `variables:` block of one file.                           |
| `varsAt [ "x" "env" ] ./f.yml`                           | Variable block at a custom attribute path.                |
| `expand { A = "$B"; B = "1"; }`                          | Reference expansion only.                                 |
| `toStr v`                                                | Coerce a scalar (bool/int/null/...) to a string.          |

### `load` options

- `files`: list of YAML files, later ones override earlier ones.
- `extra`: attrset merged last, for values only known outside of CI.
- `attrPath`: where the variables live inside each file (default `[ "variables" ]`).
- `keepEmpty`: keep variables that expand to `""` (default: drop them).
- `expandRefs`: perform `$VAR` expansion (default: `true`).

The library-level `defaultAttrPath` argument changes the default `attrPath`
for all entry points:

```nix
yamlVars = nix-yaml-vars.lib {
  inherit pkgs;
  defaultAttrPath = [ "x" "variables" ];
};
```

## Expansion semantics

- Both `$FOO` and `${FOO}` forms are supported.
- Values may reference other values in any order; expansion iterates to a
  fixed point (bounded at 100 iterations, so circular references are an
  eval error naming the offending variables rather than a hang).
- Unknown names expand to `""`.
- Non-string scalars (ints, bools, `null`) are coerced to strings.

## Note on import-from-derivation

This uses IFD: `yq-go` converts YAML to JSON at eval time. devenv and plain
`nix` allow this by default, but evaluators running with restricted eval
(e.g. some Hydra setups) will reject it.

## Tests

```sh
nix flake check
# or without flakes:
nix-build tests.nix --arg pkgs 'import <nixpkgs> {}'
```

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
