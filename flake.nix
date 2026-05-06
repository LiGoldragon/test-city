{
  description = "test-city — sandbox for reproducing Gas City bugs in canonical isolated cities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    gascity-v1-0 = {
      url = "github:gastownhall/gascity/v1.0.0";
      flake = false;
    };

    gascity-upstream-main = {
      url = "github:gastownhall/gascity/4be4d44be6df85b1c8b7f20c4afcc98fc1713dcc";
      flake = false;
    };

    gascity-fork-issue-prefix = {
      url = "github:LiGoldragon/gascity/89b035f0d5a767668f6878d5229a46096f3cb2da";
      flake = false;
    };

    gascity-fork-dolt-amp = {
      url = "github:LiGoldragon/gascity/6462edf36cefa88bde03f19439173a3bc821a708";
      flake = false;
    };

    # Kept available for later fork/upstream comparison apps. The default
    # runner below uses the direct stock v1.0.0 input.
    gascity-nix = {
      url = "github:LiGoldragon/gascity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, gascity-nix, gascity-v1-0, gascity-upstream-main, gascity-fork-issue-prefix, gascity-fork-dolt-amp, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gascity-nix.overlays.default ];
        };

        sourceRoot = ./.;
        stockGascityCommit = "67c821c76f17226883e7153a324dadcfe80ec211";
        upstreamMainGascityCommit = "4be4d44be6df85b1c8b7f20c4afcc98fc1713dcc";
        forkIssuePrefixGascityCommit = "89b035f0d5a767668f6878d5229a46096f3cb2da";
        forkDoltAmpGascityCommit = "6462edf36cefa88bde03f19439173a3bc821a708";
        gascityNixPinnedCommit = "6462edf36cefa88bde03f19439173a3bc821a708";
        stockPrebuiltAssets = {
          x86_64-linux = {
            url = "https://github.com/gastownhall/gascity/releases/download/v1.0.0/gascity_1.0.0_linux_amd64.tar.gz";
            hash = "sha256-zEXmvlTGuwD+aRWCn4vquyWlhbYEpHhGhFqnuacDcNM=";
          };
          aarch64-linux = {
            url = "https://github.com/gastownhall/gascity/releases/download/v1.0.0/gascity_1.0.0_linux_arm64.tar.gz";
            hash = "sha256-DTEHuDyk460zzG4UWEQHnR9AJzBMYh4HHy8IXGTZpno=";
          };
          x86_64-darwin = {
            url = "https://github.com/gastownhall/gascity/releases/download/v1.0.0/gascity_1.0.0_darwin_amd64.tar.gz";
            hash = "sha256-1051hj7RacC12/a2X5My980BbbEyEcyKQ4+A57glMZw=";
          };
          aarch64-darwin = {
            url = "https://github.com/gastownhall/gascity/releases/download/v1.0.0/gascity_1.0.0_darwin_arm64.tar.gz";
            hash = "sha256-S2zb/9UotLKYUQj82OIS0m3s7uzHjkso+VoJx+MJFFk=";
          };
        };

        mkGascity = { version, commit, source, vendorHash ? "sha256-d1esYYBayZ6oFFGC+5/ufa0n8XXrZX5cZa0Lns+NB7s=" }:
          pkgs.buildGo125Module {
            pname = "gascity";
            inherit version;
            src = source;

            inherit vendorHash;

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

        gascityUpstreamMain = mkGascity {
          version = "1.0.0-upstream-main-2026-05-05";
          commit = upstreamMainGascityCommit;
          source = gascity-upstream-main;
        };

        gascityForkIssuePrefix = mkGascity {
          version = "1.0.0-fork-issue-prefix-2026-05-06";
          commit = forkIssuePrefixGascityCommit;
          source = gascity-fork-issue-prefix;
        };

        gascityForkDoltAmp = mkGascity {
          version = "1.0.0-fork-dolt-amp-2026-05-06";
          commit = forkDoltAmpGascityCommit;
          source = gascity-fork-dolt-amp;
        };

        gascityStockV1Prebuilt =
          let
            asset = stockPrebuiltAssets.${system} or (throw "No Gas City v1.0.0 prebuilt asset for ${system}");
          in
          pkgs.stdenvNoCC.mkDerivation {
            pname = "gascity-prebuilt";
            version = "1.0.0";
            src = pkgs.fetchurl asset;
            dontPatchELF = true;

            unpackPhase = ''
              runHook preUnpack
              mkdir source
              tar -xzf "$src" -C source
              cd source
              runHook postUnpack
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 gc "$out/bin/gc"
              install -Dm644 LICENSE "$out/share/licenses/gascity/LICENSE"
              install -Dm644 README.md "$out/share/doc/gascity/README.md"
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Prebuilt upstream Gas City v1.0.0 release binary";
              homepage = "https://github.com/gastownhall/gascity/releases/tag/v1.0.0";
              license = licenses.mit;
              mainProgram = "gc";
              platforms = builtins.attrNames stockPrebuiltAssets;
            };
          };

        cityRuntimeDepsWithoutGascity = with pkgs; [
          dolt
          beads
          tmux
          git
          jq
          lsof
          procps
          util-linux
        ];

        cityRuntimeDeps = gascityPackage: [
          gascityPackage
        ] ++ cityRuntimeDepsWithoutGascity;

        harnessDeps = with pkgs; [
          bash
          coreutils
          gnused
          gawk
          findutils
          jq
          shellcheck
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

        mkIdleDoltAmpRunner = { name, gascityPackage, release, commit, provenance }:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = cityRuntimeDeps gascityPackage ++ harnessDeps;
            text = ''
              export TEST_CITY_SOURCE_ROOT=${sourceRoot}
              export TEST_CITY_GASCITY_RELEASE=${release}
              export TEST_CITY_GASCITY_COMMIT=${commit}
              export TEST_CITY_BINARY_LANE=${provenance}
              exec ${pkgs.bash}/bin/bash ${sourceRoot}/scripts/${name}.sh "$@"
            '';
          };

        runIdlePathGc = pkgs.writeShellApplication {
          name = "run-idle-path-gc";
          runtimeInputs = cityRuntimeDepsWithoutGascity ++ harnessDeps;
          text = ''
            export TEST_CITY_SOURCE_ROOT=${sourceRoot}
            exec ${pkgs.bash}/bin/bash ${sourceRoot}/scripts/run-idle-path-gc.sh "$@"
          '';
        };

        runIdleStockSource = mkIdleDoltAmpRunner {
          name = "run-idle-stock-source";
          gascityPackage = gascityStockV1;
          release = "stock-v1.0.0";
          commit = stockGascityCommit;
          provenance = "source-built";
        };

        runIdleStockPrebuilt = mkIdleDoltAmpRunner {
          name = "run-idle-stock-prebuilt";
          gascityPackage = gascityStockV1Prebuilt;
          release = "stock-v1.0.0";
          commit = stockGascityCommit;
          provenance = "upstream-prebuilt";
        };

        runIdleUpstreamMainSource = mkIdleDoltAmpRunner {
          name = "run-idle-upstream-main-source";
          gascityPackage = gascityUpstreamMain;
          release = "upstream-main";
          commit = upstreamMainGascityCommit;
          provenance = "source-built";
        };

        runIdleGascityNixSource = mkIdleDoltAmpRunner {
          name = "run-idle-gascity-nix-source";
          gascityPackage = pkgs.gascity;
          release = "gascity-nix";
          commit = gascityNixPinnedCommit;
          provenance = "source-built";
        };

        runIdleGascityIssuePrefixSource = mkIdleDoltAmpRunner {
          name = "run-idle-gascity-issue-prefix-source";
          gascityPackage = gascityForkIssuePrefix;
          release = "gascity-issue-prefix-fix";
          commit = forkIssuePrefixGascityCommit;
          provenance = "source-built";
        };

        runIdleGascityDoltAmpSource = mkIdleDoltAmpRunner {
          name = "run-idle-gascity-dolt-amp-source";
          gascityPackage = gascityForkDoltAmp;
          release = "gascity-dolt-amp-fix";
          commit = forkDoltAmpGascityCommit;
          provenance = "source-built";
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
            echo "Run idle source: nix run .#run-idle-stock-source"
            echo "Run idle prebuilt: nix run .#run-idle-stock-prebuilt"
            echo "Run idle upstream main: nix run .#run-idle-upstream-main-source -- upstream-main"
            echo "Run idle gascity-nix: nix run .#run-idle-gascity-nix-source"
            echo "Run idle gascity issue-prefix fix: nix run .#run-idle-gascity-issue-prefix-source"
            echo "Run idle gascity dolt-amp fix: nix run .#run-idle-gascity-dolt-amp-source"
            echo "Run idle PATH gc: nix run .#run-idle-path-gc"
            echo "Tear down: nix run .#tear-down -- /tmp/test-city..."
          '';
        };

        packages = {
          default = prepareStockCity;
          prepare-test-city = prepareStockCity;
          tear-down-test-city = tearDownTestCity;
          gascity-stock-v1-0 = gascityStockV1;
          gascity-stock-v1-0-prebuilt = gascityStockV1Prebuilt;
          gascity-upstream-main = gascityUpstreamMain;
          gascity-issue-prefix-fix = gascityForkIssuePrefix;
          gascity-dolt-amp-fix = gascityForkDoltAmp;
          gascity-current-fork = pkgs.gascity;
          run-idle-stock-source = runIdleStockSource;
          run-idle-stock-prebuilt = runIdleStockPrebuilt;
          run-idle-upstream-main-source = runIdleUpstreamMainSource;
          run-idle-gascity-nix-source = runIdleGascityNixSource;
          run-idle-gascity-issue-prefix-source = runIdleGascityIssuePrefixSource;
          run-idle-gascity-dolt-amp-source = runIdleGascityDoltAmpSource;
          run-idle-path-gc = runIdlePathGc;
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
          run-idle-stock-source = {
            type = "app";
            program = "${runIdleStockSource}/bin/run-idle-stock-source";
          };
          run-idle-stock-prebuilt = {
            type = "app";
            program = "${runIdleStockPrebuilt}/bin/run-idle-stock-prebuilt";
          };
          run-idle-upstream-main-source = {
            type = "app";
            program = "${runIdleUpstreamMainSource}/bin/run-idle-upstream-main-source";
          };
          run-idle-gascity-nix-source = {
            type = "app";
            program = "${runIdleGascityNixSource}/bin/run-idle-gascity-nix-source";
          };
          run-idle-gascity-issue-prefix-source = {
            type = "app";
            program = "${runIdleGascityIssuePrefixSource}/bin/run-idle-gascity-issue-prefix-source";
          };
          run-idle-gascity-dolt-amp-source = {
            type = "app";
            program = "${runIdleGascityDoltAmpSource}/bin/run-idle-gascity-dolt-amp-source";
          };
          run-idle-path-gc = {
            type = "app";
            program = "${runIdlePathGc}/bin/run-idle-path-gc";
          };
        };
      }
    );
}
