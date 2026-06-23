{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  makeWrapper,
  undmg,
  google-chrome,
  # Additional libraries for Electron/webview support
  libxkbfile,
  libsecret,
  libGL,
  libdrm,
  mesa,
  nss,
  nspr,
  at-spi2-atk,
  at-spi2-core,
  libxkbcommon,
  xorg,
  wayland,
  gtk3,
  glib,
  pango,
  cairo,
  gdk-pixbuf,
  libnotify,
  cups,
  libpulseaudio,
  systemd,
}:

let
  pname = "cursor";
  version = "3.8.22";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/production/46fb7aafe279d7c72346febe68c2e004b7d1de6e/linux/x64/Cursor-${version}-x86_64.AppImage";
      hash = "sha256-yt/hQdgl6jyxJVL8Y0Sduwyorq6dpwff265ikW60hXI=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/production/46fb7aafe279d7c72346febe68c2e004b7d1de6e/linux/arm64/Cursor-${version}-aarch64.AppImage";
      hash = "sha256-+Dab24+PgjZVOr0J4K9VoPpjWi/lYANu47kftiQJIAQ=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/production/46fb7aafe279d7c72346febe68c2e004b7d1de6e/darwin/x64/Cursor-darwin-x64.dmg";
      hash = "sha256-Xr0lWlbtDcGif79do+/+hvkpJOZr1/X/KHb4bCV3itM=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/production/46fb7aafe279d7c72346febe68c2e004b7d1de6e/darwin/arm64/Cursor-darwin-arm64.dmg";
      hash = "sha256-aYJILbLYkukePa3l9CeLvbnmIfi0s0GUggTL9AaJQOo=";
    };
  };

  source = sources.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  appimageContents = appimageTools.extractType2 {
    inherit pname version;
    src = source;
  };
in
if stdenv.hostPlatform.isLinux then
  appimageTools.wrapType2 {
    inherit pname version;
    src = source;

    # Include Chrome and essential Electron/webview libraries in FHS environment
    extraPkgs = pkgs: [
      google-chrome
      # Keyboard/input handling (fixes native-keymap errors)
      libxkbfile
      libxkbcommon
      xorg.libxkbfile
      # Security/credentials
      libsecret
      nss
      nspr
      # Graphics/GPU
      libGL
      libdrm
      mesa
      # GTK/display
      gtk3
      glib
      pango
      cairo
      gdk-pixbuf
      # Accessibility (needed for BrowserView)
      at-spi2-atk
      at-spi2-core
      # Wayland support
      wayland
      # System integration
      libnotify
      cups
      libpulseaudio
      systemd
      # X11 libraries
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libxcb
    ];

    # Ensure Chrome is accessible with standard names
    extraBwrapArgs = [
      "--setenv CHROME_BIN ${google-chrome}/bin/google-chrome-stable"
      "--setenv CHROME_PATH ${google-chrome}/bin/google-chrome-stable"
    ];

    extraInstallCommands = ''
      # Install desktop file and icons
      install -Dm444 ${appimageContents}/cursor.desktop -t $out/share/applications
      substituteInPlace $out/share/applications/cursor.desktop \
        --replace-fail 'Exec=cursor' 'Exec=${pname}'

      # Copy icon files
      for size in 16 32 48 64 128 256 512 1024; do
        if [ -f ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/cursor.png ]; then
          install -Dm444 ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/cursor.png \
            $out/share/icons/hicolor/''${size}x''${size}/apps/cursor.png
        fi
      done
    '';

    meta = with lib; {
      description = "AI-powered code editor built on VS Code";
      homepage = "https://cursor.com";
      changelog = "https://www.cursor.com/changelog";
      license = licenses.unfree;
      maintainers = [ ];
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mainProgram = "cursor";
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  }
else if stdenv.hostPlatform.isDarwin then
  stdenv.mkDerivation {
    inherit pname version;
    src = source;

    nativeBuildInputs = [ undmg ];

    sourceRoot = "Cursor.app";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications/Cursor.app
      cp -R . $out/Applications/Cursor.app
      runHook postInstall
    '';

    meta = with lib; {
      description = "AI-powered code editor built on VS Code";
      homepage = "https://cursor.com";
      changelog = "https://www.cursor.com/changelog";
      license = licenses.unfree;
      maintainers = [ ];
      platforms = lib.platforms.darwin;
      mainProgram = "cursor";
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  }
else
  throw "Unsupported platform: ${stdenv.hostPlatform.system}"
