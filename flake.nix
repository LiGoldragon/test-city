{
  description = "test-city — sandbox for reproducing Gas City bugs in canonical isolated cities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    gascity-v1-0 = {
      url = "github:gastownhall/gascity/v1.0.0";
      flake = false;
    };

    # Kept available for later fork/upstream comparison apps. The default
    # runner below uses the direct stock v1.0.0 input.
    gascity-nix = {
      url = "github:LiGoldragon/gascity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, gascity-nix, gascity-v1-0, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gascity-nix.overlays.default ];
        };

        sourceRoot = ./.;
        stockGascityCommit = "67c821c76f17226883e7153a324dadcfe80ec211";

        mkGascity = { version, commit, source }:
          pkgs.buildGo125Module {
            pname = "gascity";
            inherit version;
            src = source;

            vendorHash = "sha256-d1esYYBayZ6oFFGC+5/ufa0n8XXrZX5cZa0Lns+NB7s=";

            # Packaging compatibility for NixOS: the embedded bd helper
            # scripts are bash-shaped but tagged /bin/sh in v1.0.0.
            postPatch = ''
              find examples -name '*.sh' -print0 \
                | xargs -0 sed -i '1s|^#!/bin/sh$|#!${pkgs.bash}/bin/bash|'
            '';

            subPackages = [ "cmd/gc" ];

            ldflags = [
              "-X main.version=${version}"
              "-X main.commit=${commit}"
              "-X main.date=1970-01-01T00:00:00Z"
            ];

            doCheck = false;

            meta = with pkgs.lib; {
              description = "Orchestration-builder SDK for multi-agent coding workflows";
              homepage = "https://github.com/gastownhall/gascity";
              license = licenses.mit;
              mainProgram = "gc";
              platforms = platforms.unix;
            };
          };

        gascityStockV1 = mkGascity {
          version = "1.0.0";
          commit = stockGascityCommit;
          source = gascity-v1-0;
        };

        cityRuntimeDeps = gascityPackage: with pkgs; [
          gascityPackage
          dolt
          beads
          tmux
          git
          jq
          lsof
          procps
          util-linux
        ];

        harnessDeps = with pkgs; [
          bash
          coreutils
          gnused
          gawk
          findutils
          jq
        ];

        prepareStockCity = pkgs.writeShellApplication {
          name = "prepare-test-city";
          runtimeInputs = cityRuntimeDeps gascityStockV1 ++ harnessDeps;
          text = ''
            export TEST_CITY_SOURCE_ROOT=${sourceRoot}
            export TEST_CITY_GASCITY_RELEASE=stock-v1.0.0
            export TEST_CITY_GASCITY_COMMIT=${stockGascityCommit}
            exec ${pkgs.bash}/bin/bash ${sourceRoot}/scripts/prepare-test-city.sh "$@"
          '';
        };

        tearDownTestCity = pkgs.writeShellApplication {
          name = "tear-down-test-city";
          runtimeInputs = harnessDeps;
          text = ''
            export TEST_CITY_SOURCE_ROOT=${sourceRoot}
            exec ${pkgs.bash}/bin/bash ${sourceRoot}/scripts/tear-down-test-city.sh "$@"
          '';
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "test-city-shell";
          packages = cityRuntimeDeps gascityStockV1 ++ harnessDeps;

          shellHook = ''
            echo "test-city shell — gascity $(gc version 2>/dev/null | head -1)"
            echo "Available templates: $(ls templates 2>/dev/null | tr '\n' ' ')"
            echo "Prepare: nix run . -- <template>"
            echo "Tear down: nix run .#tear-down -- /tmp/test-city..."
          '';
        };

        packages = {
          default = prepareStockCity;
          prepare-test-city = prepareStockCity;
          tear-down-test-city = tearDownTestCity;
          gascity-stock-v1-0 = gascityStockV1;
          gascity-current-fork = pkgs.gascity;
        };

        apps = {
          default = {
            type = "app";
            program = "${prepareStockCity}/bin/prepare-test-city";
          };
          prepare = {
            type = "app";
            program = "${prepareStockCity}/bin/prepare-test-city";
          };
          tear-down = {
            type = "app";
            program = "${tearDownTestCity}/bin/tear-down-test-city";
          };
        };
      }
    );
}
