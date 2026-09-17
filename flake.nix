{
  description = "Rune — the development environment for pros";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      # | Platform         | Upstream Rune target | Nix packaging |
      # | ---------------- | -------------------- | ------------- |
      # | `x86_64-linux`   | `linux-amd64`        | Working       |
      # | `aarch64-linux`  | `linux-arm64`        | Resolve       |
      # | `x86_64-darwin`  | `darwin-amd64`       | Resolve       |
      # | `aarch64-darwin` | `darwin-arm64`       | Resolve       |
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # Keep this version string equal to the git release tag.
      version = "1.2.1";

      # Format the build date as an RFC3339 UTC string. This string matches internal/debug.BuildDateLayout ("2006-01-02T15:04:05Z07:00").
      sourceDate =
        let
          date = self.lastModifiedDate or "19700101000000";
        in
        "${builtins.substring 0 4 date}-${builtins.substring 4 2 date}-${builtins.substring 6 2 date}T${builtins.substring 8 2 date}:${builtins.substring 10 2 date}:${builtins.substring 12 2 date}Z";

      rune = pkgs.buildGoModule {
        pname = "rune-ide";
        inherit version;

        src = self;

        vendorHash = "sha256-uWG5MW2ZsFMx6JIAUaU9LsN9wSr/LA1W/y6iB+uVebI=";
        subPackages = [
          "cmd/rune"
        ];

        nativeBuildInputs = [
          pkgs.pkg-config
          pkgs.makeWrapper
        ];

        buildInputs = [
          pkgs.alsa-lib
          pkgs.libGL
          pkgs.libX11
          pkgs.libXcursor
          pkgs.libXext
          pkgs.libXi
          pkgs.libXinerama
          pkgs.libXrandr
          pkgs.libXrender
          pkgs.libXxf86vm
          pkgs.libxkbcommon
          pkgs.wayland
        ];

        nativeCheckInputs = [
          pkgs.xvfb-run
        ];

        tags = [
          "ebitensinglethread"
        ];

        ldflags = [
          "-X unstable.build/rune/internal/debug.Tag=v${version}"
          "-X unstable.build/rune/internal/debug.Commit=${self.shortRev or "unknown"}"
          "-X unstable.build/rune/internal/debug.BuildDate=${sourceDate}"
          "-X unstable.build/rune/internal/debug.Package=rune"
        ];

        env.CGO_ENABLED = "1";

        # Tree-sitter Workaround:
        # Rune uses a vendored fork of go-tree-sitter (github.com/unstablebuild/go-tree-sitter).
        # The compilation requires C source files in src/ and include/.
        # Standard `go mod vendor` removes C source files from vendor directories.
        # The modPostBuild hook copies the C source files from the module cache to the vendor directory.
        modPostBuild = ''
          tree_sitter_module="$GOPATH/pkg/mod/github.com/unstablebuild/go-tree-sitter@v0.25.0-ub.1"
          tree_sitter_vendor="vendor/github.com/tree-sitter/go-tree-sitter"

          cp -r "$tree_sitter_module/src" "$tree_sitter_vendor/"
          cp -r "$tree_sitter_module/include" "$tree_sitter_vendor/"
        '';

        # Ebitengine GL Wrapper Requirement:
        # Rune depends on Ebitengine, which dynamically loads OpenGL libraries (`libGL.so`, `libGLESv2.so`)
        # at runtime by filename. On NixOS, placing `libGL` in `buildInputs` provides the library at build time,
        # but runtime dynamic loading fails because shared objects are not in standard dynamic linker paths.
        # Prefixing `LD_LIBRARY_PATH` with `${pkgs.libGL}/lib` via `wrapProgram` makes these unversioned shared
        # libraries discoverable at runtime without patching vendored Ebitengine code.
        postInstall = ''
          wrapProgram $out/bin/rune \
            --prefix LD_LIBRARY_PATH : "${pkgs.libGL}/lib"
        '';

        checkPhase = ''
          runHook preCheck

          export GOFLAGS=''${GOFLAGS//-trimpath/}
          export HOME="$(mktemp -d)"

          xvfb-run -a -s '-screen 0 1920x1080x24' \
            go test -vet=off ''${checkFlags[@]} ./cmd/rune

          runHook postCheck
        '';

        meta = {
          description = "Fast, GPU-rendered, keyboard-driven IDE";
          homepage = "https://rune.build";
          license = pkgs.lib.licenses.gpl3Plus;
          mainProgram = "rune";
          platforms = [ "x86_64-linux" ];
        };
      };
    in
    {
      packages.x86_64-linux = {
        default = rune;
        rune-ide = rune;
        rune = rune;
      };

      apps.x86_64-linux.default = {
        type = "app";
        program = "${rune}/bin/rune";
      };

      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [
          pkgs.go
          pkgs.gopls
          pkgs.git
          pkgs.gnumake
          pkgs.xvfb-run
        ];

        nativeBuildInputs = [
          pkgs.pkg-config
        ];

        buildInputs = [
          pkgs.alsa-lib
          pkgs.libGL
          pkgs.libX11
          pkgs.libXcursor
          pkgs.libXext
          pkgs.libXi
          pkgs.libXinerama
          pkgs.libXrandr
          pkgs.libXrender
          pkgs.libXxf86vm
          pkgs.libxkbcommon
          pkgs.wayland
        ];

        env.CGO_ENABLED = "1";

        shellHook = ''
          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.libGL ]}:''${LD_LIBRARY_PATH:-}"
        '';
      };
    };
}
