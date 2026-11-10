# Based on nixpkgs/pkgs/by-name/am/amp-cli/package.nix
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  gzip,
  makeWrapper,
  ripgrep,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}: let
  release = (builtins.fromJSON (builtins.readFile ./sources.json)).sources.cli;
  source = release.platforms.${stdenvNoCC.hostPlatform.system};
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "amp-cli";
    inherit (source) version;

    src = fetchurl {
      url = "https://static.ampcode.com/cli/${finalAttrs.version}/amp-${source.platform}.gz";
      inherit (source) hash;
    };

    nativeBuildInputs = [autoPatchelfHook gzip makeWrapper];
    strictDeps = true;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/libexec/amp-cli"
      gunzip -c "$src" > "$out/libexec/amp-cli/amp"
      chmod +x "$out/libexec/amp-cli/amp"
      makeWrapper "$out/libexec/amp-cli/amp" "$out/bin/amp" \
        --set AMP_SKIP_UPDATE_CHECK 1 \
        --prefix PATH : ${lib.makeBinPath [ripgrep]}
      runHook postInstall
    '';

    doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
    nativeInstallCheckInputs = [writableTmpDirAsHomeHook versionCheckHook];
    versionCheckProgram = "${placeholder "out"}/bin/amp";
    versionCheckProgramArg = "--version";
    versionCheckKeepEnvironment = ["HOME"];

    meta = {
      description = "CLI for Amp, a coding agent";
      homepage = "https://ampcode.com/";
      license = lib.licenses.unfree;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = builtins.attrNames release.platforms;
      mainProgram = "amp";
    };
  })
