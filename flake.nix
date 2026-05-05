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

    # Kept available for later fork/upstream comparison apps. The default
    # runner below uses the direct stock v1.0.0 input.
    gascity-nix = {
      url = "github:LiGoldragon/gascity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, gascity-nix, gascity-v1-0, gascity-upstream-main, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gascity-nix.overlays.default ];
        };

        sourceRoot = ./.;
        stockGascityCommit = "67c821c76f17226883e7153a324dadcfe80ec211";
        upstreamMainGascityCommit = "4be4d44be6df85b1c8b7f20c4afcc98fc1713dcc";
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
          gascity-current-fork = pkgs.gascity;
          run-idle-stock-source = runIdleStockSource;
          run-idle-stock-prebuilt = runIdleStockPrebuilt;
          run-idle-upstream-main-source = runIdleUpstreamMainSource;
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
        };
      }
    );
}
