{
  description = "A Nix flake to package the Kiro IDE.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        lib = pkgs.lib;

        version = "0.1.15";

        # Define libraries separately so we can reference them in postFixup
        libs = with pkgs; [
          gtk3
          alsa-lib
          at-spi2-atk
          at-spi2-core
          cups
          dbus
          expat
          nss
          nspr
          pipewire
          libdrm
          mesa
          libGL
          libglvnd
          libxkbcommon
          pango
          cairo
          gdk-pixbuf
          glib
          freetype
          fontconfig
          libnotify
          xorg.libX11
          xorg.libXcomposite
          xorg.libXdamage
          xorg.libXext
          xorg.libXfixes
          xorg.libXrandr
          xorg.libxcb
          xorg.libxshmfence
          xorg.libxkbfile
          xorg.libXi
          xorg.libXrender
          xorg.libXtst
          xorg.libXScrnSaver
          xorg.libXcursor
          xorg.libXinerama
          libpulseaudio
          systemd
          udev
        ];

        kiro = pkgs.stdenv.mkDerivation {
          pname = "kiro";
          inherit version;
          src = pkgs.fetchurl {
            url = "https://prod.download.desktop.kiro.dev/releases/202507180237--distro-linux-x64-tar-gz/202507180237-distro-linux-x64.tar.gz";
            sha256 = "01vg1wwskgpq8jwwr2gh7f4xsba79ajlwsxqgdvr84aac38wcw3i";
          };

          sourceRoot = "Kiro";

          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.autoPatchelfHook
            pkgs.wrapGAppsHook
          ];

          buildInputs = libs;

          runtimeDependencies = [
            pkgs.libglvnd
            pkgs.mesa
            pkgs.mesa.drivers
            pkgs.vulkan-loader
          ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/kiro
            cp -r ./* $out/lib/kiro/
            
            # Remove chrome-sandbox to force --no-sandbox mode
            rm -f $out/lib/kiro/chrome-sandbox
            
            runHook postInstall
          '';

          postFixup = ''
            # Create a launcher script that explicitly sets --no-sandbox
            mkdir -p $out/bin
            cat > $out/bin/kiro << 'EOF'
            #!/bin/sh
            export LD_LIBRARY_PATH="${lib.makeLibraryPath libs}:${pkgs.libglvnd}/lib:${pkgs.mesa}/lib:${pkgs.mesa.drivers}/lib:$LD_LIBRARY_PATH"
            export __EGL_VENDOR_LIBRARY_DIRS="${pkgs.mesa.drivers}/share/glvnd/egl_vendor.d"
            export LIBGL_DRIVERS_PATH="${pkgs.mesa.drivers}/lib/dri"
            export LIBVA_DRIVERS_PATH="${pkgs.mesa.drivers}/lib/dri"
            export NIXOS_OZONE_WL="1"
            
            # Force no sandbox mode
            exec "$out/lib/kiro/kiro" --no-sandbox "$@"
            EOF
            
            chmod +x $out/bin/kiro
            
            # Also try the bin/kiro if it exists
            if [ -f $out/lib/kiro/bin/kiro ]; then
              chmod +x $out/lib/kiro/bin/kiro
            fi

            # Create the desktop file
            mkdir -p $out/share/applications
            cat > $out/share/applications/kiro.desktop << 'EOF'
            [Desktop Entry]
            Name=Kiro
            Comment=Kiro - AI-powered development environment
            Exec=kiro %F
            Icon=kiro
            Terminal=false
            Type=Application
            Categories=Development;IDE;
            StartupWMClass=kiro
            MimeType=text/plain;
            EOF

            # Install the icon
            if [ -f $out/lib/kiro/resources/app/resources/linux/code.png ]; then
              install -Dm644 $out/lib/kiro/resources/app/resources/linux/code.png \
                $out/share/icons/hicolor/512x512/apps/kiro.png
            fi
            
            # Substitute the correct output path in the launcher
            substituteInPlace $out/bin/kiro --replace '$out' "$out"
          '';

          meta = {
            description = "Kiro - AI-powered development environment";
            homepage = "https://kiro.dev/";
            license = lib.licenses.unfree;
            platforms = [ "x86_64-linux" ];
            maintainers = with lib.maintainers; [ ];
          };
        };

      in
      {
        packages = {
          inherit kiro;
          default = kiro;
        };

        apps = {
          kiro = {
            type = "app";
            program = "${kiro}/bin/kiro";
            meta.description = "Launch the Kiro IDE";
          };
          default = self.apps.${system}.kiro;
        };
      });
}