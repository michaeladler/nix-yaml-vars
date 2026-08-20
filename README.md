# nix-yaml-vars

A small, project-agnostic Nix library for reading `variables:` blocks out of
YAML files (GitLab CI templates, docker-compose files, plain YAML, ...) and
turning them into a flat attrset of strings suitable for `env`.

It makes no assumptions about file layout: every path is passed in by the
caller.

## Usage

As a flake input:

```nix
{
  inputs.nix-yaml-vars.url = "https://github.com/michaeladler/nix-yaml-vars";

  outputs = { nixpkgs, nix-yaml-vars, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      yamlVars = nix-yaml-vars.lib { inherit pkgs; };
    in {
      # merge the `variables:` blocks of several files, then expand
      # $FOO / ${FOO} references
      env = yamlVars.load {
        files = [ ./ci/templates/base.yml ./ci/env/dev-eu.yml ];
        extra = { AWS_ACCOUNT_ID = "1234567890"; };
      };
    };
}
```

With devenv, add to `devenv.yaml`:

```yaml
inputs:
  nix-yaml-vars:
    url: github:michaeladler/nix-yaml-vars
```

and use `inputs.nix-yaml-vars.lib { inherit pkgs; }` in `devenv.nix`.

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

- `files` — list of YAML files, later ones override earlier ones.
- `extra` — attrset merged last, for values only known outside of CI.
- `attrPath` — where the variables live inside each file (default `[ "variables" ]`).
- `keepEmpty` — keep variables that expand to `""` (default: drop them).
- `expandRefs` — perform `$VAR` expansion (default: `true`).

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
