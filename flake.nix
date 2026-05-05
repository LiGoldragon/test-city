{
  description = "test-city — sandbox for reproducing Gas City bugs in canonical isolated cities";

  # Scaffold authored by mayor (Claude) on 2026-05-05; codex is expected to
  # extend this flake with real test scenarios. The shape below is minimal
  # and intentionally close to the orchestrator repo's pattern.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Default gascity package source. Override per-template by re-pinning
    # this input to a specific commit (e.g., upstream v1.0.0, upstream main,
    # a fork branch).
    gascity-nix = {
      url = "github:LiGoldragon/gascity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Optional: orchestrator daemon for cascade-dispatch test scenarios.
    # Uncomment when wiring in cascade tests.
    # orchestrator = {
    #   url = "github:LiGoldragon/orchestrator";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, flake-utils, gascity-nix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gascity-nix.overlays.default ];
        };

        # Runtime deps a test city needs: gc itself plus everything gc
        # shells out to. Mirrors gascity-nix's runtimeDeps list.
        cityRuntimeDeps = with pkgs; [
          gascity
          dolt
          beads
          tmux
          git
          jq
          lsof
          procps
          util-linux
        ];

        # Tools the test harness itself uses for spinning up + tearing
        # down test cities and capturing diagnostics.
        harnessDeps = with pkgs; [
          bash
          coreutils
          gnused
          gawk
          findutils
          python3
          curl
        ];
      in
      {
        # Default devShell: drop into a shell that has `gc` + runtime deps
        # on PATH. From here, `bash scripts/spawn-test-city.sh <template>`
        # to spin up an ephemeral test city in a mktemp scratch root.
        devShells.default = pkgs.mkShell {
          name = "test-city-shell";
          packages = cityRuntimeDeps ++ harnessDeps;

          shellHook = ''
            echo "test-city shell — gascity $(gc version 2>/dev/null | head -1)"
            echo "Available templates: $(ls templates 2>/dev/null | tr '\n' ' ')"
            echo "Spin up: bash scripts/spawn-test-city.sh <template>"
            echo "Tear down: rm -rf \$TEST_CITY_ROOT (set by spawn script)"
          '';
        };

        # Expose the gascity package directly so test scripts can reference
        # the binary path without going through the shell.
        packages.gascity = pkgs.gascity;
        packages.default = pkgs.gascity;
      }
    );
}
