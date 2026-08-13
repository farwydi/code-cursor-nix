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
  version = "3.15.19";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/production/de07bee81cefe43461ebf4f40c3d2d78d15052aa/linux/x64/Cursor-${version}-x86_64.AppImage";
      hash = "sha256-lSzgIyQgWNg3rOBZ0UMRbWAUHcY2GLuTZYbLHlBwbSY=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/production/de07bee81cefe43461ebf4f40c3d2d78d15052aa/linux/arm64/Cursor-${version}-aarch64.AppImage";
      hash = "sha256-NZVYiyu02lSpqVYc24bzwrh7Xc1hhzuHZnNvq9BQlwg=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/production/de07bee81cefe43461ebf4f40c3d2d78d15052aa/darwin/x64/Cursor-darwin-x64.dmg";
      hash = "sha256-oW8Gk25XPn59h/QAYvb9XCyZ8oG16Uu4xZABi2RG0Mo=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/production/de07bee81cefe43461ebf4f40c3d2d78d15052aa/darwin/arm64/Cursor-darwin-arm64.dmg";
      hash = "sha256-gYTucYvdJRejBIavaDBG6TN1EEddaKgv/9gNCN1eW48=";
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
