{
  pkgs,
  lib ? pkgs.lib,
}:

let
  yamlVars = import ./yaml-vars.nix { inherit pkgs lib; };

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
      expr = (yamlVars.expand {
        Z = "$Y";
        Y = "$X";
        X = "deep";
      }).Z;
      expected = "deep";
    };

    # Unknown names expand to the empty string rather than failing.
    testExpandUnknown = {
      expr = (yamlVars.expand { A = "x$NOPE.y"; }).A;
      expected = "x.y";
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
      expr = (yamlVars.load {
        files = [ sample ];
        keepEmpty = true;
      }).EMPTY;
      expected = "";
    };

    testLoadExtraWinsLast = {
      expr = (yamlVars.load {
        files = [ sample ];
        extra.APP = "from-extra";
      }).APP;
      expected = "from-extra";
    };

    testLoadNoExpand = {
      expr = (yamlVars.load {
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
