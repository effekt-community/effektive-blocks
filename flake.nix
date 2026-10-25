{
  description = "Html & wave function collapse";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    effekt-nix = {
      url = "github:jiribenes/effekt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, effekt-nix }:
    let
      ## Builds for all systems supported by effekt-nix.
      ## If you want only some specific systems, do the following instead:
      # systems = ["aarch64-linux" "aarch64-darwin"];
      systems = effekt-nix.lib.supportedSystems;

      forAllSystems = nixpkgs.lib.genAttrs systems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      ## Project configuration
      pname = "effektive-blocks";        # package name
      version = "0.1.0";                 # package version
      mainFile = "src/main.effekt";      # relative path to entrypoint (as a string)
      testFiles = [ "src/test.effekt" ]; # relative paths to tests (as a string)

      ## Effekt configuration
      effektConfig = {
        ## Uncomment and set a specific version if needed:
        # version = "0.82.0";

        ## Select the backends that your project works on (CI builds and tests each one):
        backends = bs: [ bs.js-web ];
      };

      perSystem = system:
        let
          pkgs = nixpkgsFor.${system};
          effekt-lib = effekt-nix.lib.mkLib pkgs;

          # Chooses the correct Effekt package.
          effektBuild = effekt-lib.getEffekt effektConfig;

          # The npm packages the tests 'require' (pinned by 'package-lock.json'), built for the Node.js that runs them
          nodeModules = pkgs.importNpmLock.buildNodeModules {
            npmRoot = ./.;
            inherit (pkgs) nodejs;
            derivationArgs = {
              pname = "${pname}-node-modules";
              inherit version;
              # 'canvas' is native: build it against nixpkgs' libraries instead of downloading a prebuilt binary
              env.npm_config_build_from_source = "canvas";
              nativeBuildInputs = [ pkgs.pkg-config ];
              buildInputs = [ pkgs.cairo pkgs.pango pkgs.pixman pkgs.libjpeg pkgs.giflib pkgs.librsvg ];
            };
          };

          package = effekt-lib.buildEffektPackage {
            inherit pname version;
            src = ./.;
            main = mainFile;
            tests = testFiles;
            meta.platforms = systems;

            effektFlags = [ "--no-optimize" "--max-inline-size" "10" ];
            ## The tests run on Node.js and 'require' 'canvas'
            makeWrapperArgs = [ "--prefix" "NODE_PATH" ":" "${nodeModules}/node_modules" ];

            effekt = effektBuild;
            inherit (effektConfig) backends;
          };

          variants = effekt-lib.variantsOf package;
        in {
          ## The package, plus one for each backend (such as 'llvm')
          packages = variants // {
            default = package;

            ## Preview the website with 'nix run .#serve' (published by '.github/workflows/pages.yml')
            serve = effekt-lib.serveSite { site = variants.js-web; };
          };

          devShell = effekt-lib.mkDevShell {
            effekt = effektBuild;
            inherit (effektConfig) backends;

            ## Link 'nodeModules' into the project (for the tests)
            packages = [ pkgs.importNpmLock.linkNodeModulesHook ];
            npmDeps = nodeModules;
          };
        };

      allSystems = forAllSystems perSystem;
    in {
      packages = builtins.mapAttrs (system: outputs: outputs.packages) allSystems;
      devShells = builtins.mapAttrs (system: outputs: { default = outputs.devShell; }) allSystems;
    };
}
