{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  makeWrapper,
  electron_44,
  xdg-utils,
  amp-cli ? null,
}: let
  inherit (builtins.fromJSON (builtins.readFile ./sources.json)) sources;
  source = sources.${stdenvNoCC.hostPlatform.system};
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "amp-desktop";
    inherit (source) version;

    src = fetchurl {
      url = "https://static.ampcode.com/linux/${finalAttrs.version}/amp-desktop-${finalAttrs.version}-${source.arch}.deb";
      inherit (source) hash;
    };

    nativeBuildInputs = [
      dpkg
      makeWrapper
    ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/amp-desktop"
      cp opt/amp/resources/app.asar "$out/share/amp-desktop/app.asar"
      cp -r usr/share/applications usr/share/icons "$out/share/"

      makeWrapper ${lib.getExe electron_44} "$out/bin/amp-desktop" \
        --add-flags "$out/share/amp-desktop/app.asar --class=amp-desktop" \
        ${lib.optionalString (amp-cli != null) "--set-default AMP_DESKTOP_RUNNER_CLI ${lib.getExe amp-cli}"} \
        --suffix PATH : ${lib.makeBinPath [xdg-utils]} \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-wayland-ime=true}}"

      substituteInPlace "$out/share/applications/amp-desktop.desktop" \
        --replace-fail /opt/amp/amp-desktop "$out/bin/amp-desktop"
      runHook postInstall
    '';

    meta = {
      description = "Amp, the frontier coding agent, as a desktop app";
      homepage = "https://ampcode.com/docs/apps/linux";
      license = lib.licenses.unfree;
      sourceProvenance = [lib.sourceTypes.fromSource];
      platforms = builtins.attrNames sources;
      mainProgram = "amp-desktop";
    };
  })
