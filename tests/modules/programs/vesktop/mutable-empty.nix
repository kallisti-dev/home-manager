{
  config,
  lib,
  pkgs,
  ...
}:
let
  relativeDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/vesktop"
    else
      "custom-config/vesktop";
  activation = pkgs.writeShellScript "activate-vesktop-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.vesktopSettings.data}
  '';
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;
  xdg.configHome = "${config.home.homeDirectory}/custom-config";
  programs.vesktop = {
    enable = true;
    package = null;
    mutableSettings = true;
    vencord = {
      extraQuickCss = "body { color: red; }";
    };
  };

  assertions = [
    {
      assertion =
        lib.hasInfix "vesktop/settings.json" config.home.activation.vesktopSettings.data
        && !lib.hasInfix "settings/settings.json" config.home.activation.vesktopSettings.data;
      message = "Empty mixed-ownership settings must be merged only into the mutable file.";
    }
    {
      assertion =
        config.programs.vesktop.mutableSettings && !config.programs.vesktop.vencord.mutableSettings;
      message = "Empty settings must preserve independent ownership modes.";
    }
    {
      assertion = !(config.home.activation ? vesktopImmutableSettings);
      message = "Vesktop immutable cleanup must follow configured, enabled immutable files.";
    }
    {
      assertion = lib.all (package: !(lib.hasInfix "vesktop" (lib.getName package))) config.home.packages;
      message = "A null Vesktop package must not be installed.";
    }
    {
      assertion = (config.home.activation ? vesktopSettings);
      message = "Vesktop activation must follow module enablement.";
    }
    {
      assertion = config.home.activation.vesktopSettings.after == [ "linkGeneration" ];
      message = "Vesktop mutable activation must follow link generation.";
    }
  ];
  # The merge still runs, so settings removed last are removed, but without
  # a record it creates nothing.
  nmt.script = ''
    assertPathNotExists "home-files/${relativeDir}/settings.json"
    assertPathNotExists "home-files/${relativeDir}/settings/settings.json"
    assertFileContains "home-files/${relativeDir}/settings/quickCss.css" "body { color: red; }"
    export HOME=$TMPDIR/hm-user
    substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
    chmod +x "$TMPDIR/activate"
    "$TMPDIR/activate"
    assertPathNotExists "$HOME/${relativeDir}/settings.json"
    assertPathNotExists "$HOME/.local/state"
  '';
}
