{
  pkgs,
  lib ? pkgs.lib,
}:

let
  yamlVars = import ./. { inherit pkgs lib; };

  # tryEval is shallow: force the whole value so a throw inside an attribute
  # is actually caught.
  deepEval = x: builtins.deepSeq x x;

  sample = pkgs.writeText "sample.yml" ''
    variables:
      APP: demo
      REGION: eu-central-1
      BUCKET: "$APP-''${REGION}-state"
      REPLICAS: 3
      DEBUG: false
      EMPTY: ""
    other:
      variables:
        NESTED: yes-please
  '';

  override = pkgs.writeText "override.yml" ''
    variables:
      REGION: us-east-1
      EXTRA_ONLY: "$APP/''${REGION}"
  '';

  unusualPath = pkgs.runCommand "unusual-yaml-path" { } ''
    mkdir $out
    cat > "$out/sample; false.yml" <<'EOF'
    variables:
      APP: demo
    EOF
  '';

  scalarIntermediate = pkgs.writeText "scalar-intermediate.yml" ''
    parent: scalar
  '';

  results = lib.runTests {
    testToStrBool = {
      expr = yamlVars.toStr true;
      expected = "true";
    };

    testToStrNull = {
      expr = yamlVars.toStr null;
      expected = "";
    };

    testToStrInt = {
      expr = yamlVars.toStr 3;
      expected = "3";
    };

    # Both $FOO and ${FOO} forms, plus chained references.
    testExpandBothForms = {
      expr = yamlVars.expand {
        A = "1";
        B = "$A";
        C = "\${B}-\${A}";
      };
      expected = {
        A = "1";
        B = "1";
        C = "1-1";
      };
    };

    # Order of definition must not matter (fixed-point iteration).
    testExpandOutOfOrder = {
      expr =
        (yamlVars.expand {
          Z = "$Y";
          Y = "$X";
          X = "deep";
        }).Z;
      expected = "deep";
    };

    # Unknown names are an eval error in strict mode (the default).
    testExpandUnknownStrictThrows = {
      expr = (builtins.tryEval (deepEval (yamlVars.expand { A = "x$NOPE.y"; }))).success;
      expected = false;
    };

    # ... and expand to the empty string when strict mode is off.
    testExpandUnknownLenient = {
      expr = (yamlVars.expandWith false { A = "x$NOPE.y"; }).A;
      expected = "x.y";
    };

    # Only the tainted attrs throw; independent ones still evaluate.
    testExpandUnknownDoesNotPoisonOthers = {
      expr =
        (yamlVars.expand {
          A = "$NOPE";
          OK = "fine";
        }).OK;
      expected = "fine";
    };

    # load defaults to strict too.
    testLoadStrictThrows = {
      expr =
        (builtins.tryEval (
          deepEval (
            yamlVars.load {
              files = [ sample ];
              extra.BAD = "$NOPE";
            }
          )
        )).success;
      expected = false;
    };

    testLoadStrictOff = {
      expr =
        (yamlVars.load {
          files = [ sample ];
          extra.BAD = "x$NOPE.y";
          strict = false;
        }).BAD;
      expected = "x.y";
    };

    # A self-referential value is an eval error, not a hang.
    testExpandSelfCycleThrows = {
      expr = (builtins.tryEval (deepEval (yamlVars.expand { A = "$A"; }))).success;
      expected = false;
    };

    # ... and so is a longer cycle.
    testExpandIndirectCycleThrows = {
      expr =
        (builtins.tryEval (
          deepEval (
            yamlVars.expand {
              A = "$B";
              B = "$C";
              C = "$A";
            }
          )
        )).success;
      expected = false;
    };

    # Only the tainted attrs throw; independent ones still evaluate.
    testExpandCycleDoesNotPoisonOthers = {
      expr =
        (yamlVars.expand {
          A = "$A";
          OK = "fine";
        }).OK;
      expected = "fine";
    };

    # Repeating a name across separate branches is not a cycle.
    testExpandDiamondIsNotACycle = {
      expr =
        (yamlVars.expand {
          ROOT = "r";
          L = "$ROOT-l";
          R = "$ROOT-r";
          TOP = "$L/$R";
        }).TOP;
      expected = "r-l/r-r";
    };

    testFromYAML = {
      expr = (yamlVars.fromYAML sample).variables.APP;
      expected = "demo";
    };

    testVarsOf = {
      expr = (yamlVars.varsOf sample).REGION;
      expected = "eu-central-1";
    };

    testVarsAtNested = {
      expr = (yamlVars.varsAt [ "other" "variables" ] sample).NESTED;
      expected = "yes-please";
    };

    testVarsAtMissing = {
      expr = yamlVars.varsAt [ "nope" ] sample;
      expected = { };
    };

    testVarsAtScalarIntermediate = {
      expr = yamlVars.varsAt [ "parent" "variables" ] scalarIntermediate;
      expected = { };
    };

    testFromYAMLUnusualPath = {
      expr = (yamlVars.fromYAML (unusualPath + "/sample; false.yml")).variables.APP;
      expected = "demo";
    };

    testFromYAMLSourcePath = {
      expr = (yamlVars.fromYAML ./tests/fixtures/source-path.yml).variables.APP;
      expected = "from-source-path";
    };

    # Later files win, and expansion sees the merged value.
    testLoadMergeAndExpand = {
      expr = yamlVars.load {
        files = [
          sample
          override
        ];
      };
      expected = {
        APP = "demo";
        REGION = "us-east-1";
        BUCKET = "demo-us-east-1-state";
        REPLICAS = "3";
        DEBUG = "false";
        EXTRA_ONLY = "demo/us-east-1";
      };
    };

    # EMPTY is dropped by default, kept with keepEmpty.
    testLoadKeepEmpty = {
      expr =
        (yamlVars.load {
          files = [ sample ];
          keepEmpty = true;
        }).EMPTY;
      expected = "";
    };

    testLoadExtraWinsLast = {
      expr =
        (yamlVars.load {
          files = [ sample ];
          extra.APP = "from-extra";
        }).APP;
      expected = "from-extra";
    };

    testLoadNoExpand = {
      expr =
        (yamlVars.load {
          files = [ sample ];
          expandRefs = false;
        }).BUCKET;
      expected = "$APP-\${REGION}-state";
    };
  };
in
if results == [ ] then
  pkgs.runCommand "yaml-vars-tests-passed" { } "touch $out"
else
  throw "yaml-vars tests failed:\n${lib.generators.toPretty { } results}"
