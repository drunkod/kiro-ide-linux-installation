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

        src = pkgs.fetchurl {
          url = "https://prod.download.desktop.kiro.dev/releases/202507180237--distro-linux-x64-tar-gz/202507180237-distro-linux-x64.tar.gz";
          sha256 = "01vg1wwskgpq8jwwr2gh7f4xsba79ajlwsxqgdvr84aac38wcw3i";
        };

        kiro = pkgs.stdenv.mkDerivation {
          pname = "kiro";
          inherit version src;

          sourceRoot = "Kiro";

          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.autoPatchelfHook
          ];

          buildInputs = [
            pkgs.alsa-lib
            pkgs.at-spi2-atk
            pkgs.cups
            pkgs.dbus
            pkgs.expat
            pkgs.gtk3
            pkgs.xorg.libxshmfence
            pkgs.nss
            pkgs.pipewire
            pkgs.libdrm
            pkgs.libgbm
            pkgs.xorg.libxkbfile
          ];

          installPhase = ''
            runHook preInstall

            mkdir -p $out/lib/kiro
            cp -r ./* $out/lib/kiro/

            makeWrapper $out/lib/kiro/kiro $out/bin/kiro \
              --add-flags "--no-sandbox"

            # Create the .desktop file since one is not provided in the tarball
            mkdir -p $out/share/applications
            cat > $out/share/applications/kiro.desktop << EOF
            [Desktop Entry]
            Name=Kiro
            Comment=Kiro - AI-powered development environment
            Exec=$out/bin/kiro
            Icon=kiro
            Terminal=false
            Type=Application
            Categories=Development;IDE;
            StartupWMClass=kiro
            EOF

            # Use the icon we found inside the tarball
            install -Dm644 ./resources/app/resources/linux/code.png \
              $out/share/icons/hicolor/512x512/apps/kiro.png

            runHook postInstall
          '';

          meta = {
            description = "Kiro - AI-powered development environment";
            homepage = "https://kiro.dev/";
            license = lib.licenses.unfree;
            platforms = [ "x86_64-linux" ];
            maintainers = with lib.maintainers; [ ];
          };
        };

        # --- NixOS VM Test ---
        vmTest = pkgs.nixosTest {
          name = "kiro-vm-test";
          nodes.machine = {
            # This is a NixOS configuration for the VM
            imports = [ ];

            # Enable a graphical environment (X11)
            services.xserver = {
              enable = true;
              windowManager.xmonad.enable = true;
            };
            
            # **FIXED**: Correct path for autoLogin
            services.displayManager.autoLogin = {
              enable = true;
              user = "testuser";
            };

            # Create the user that will be logged in
            users.users.testuser = {
              isNormalUser = true;
            };

            # Install the Kiro package into the VM
            environment.systemPackages = [
              self.packages.${system}.default # This refers to the 'kiro' package
            ];
          };

          # This script runs on the host and controls the VM (it's Python!)
          testScript = ''
            start_all()
            machine.wait_for_unit("multi-user.target")
            machine.wait_for_x()
            machine.succeed("pgrep -u testuser xmonad")

            machine.succeed("sudo -u testuser kiro --version")

            machine.execute("sudo -u testuser DISPLAY=:0 kiro &")

            machine.sleep(10)

            machine.succeed("pgrep -f 'kiro --no-sandbox'")
          '';
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

        # Add the test to the flake's checks
        checks = {
          default = vmTest;
        };
      });
}