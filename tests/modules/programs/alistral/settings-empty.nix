{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-alistral-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.alistralMutableSettings.data}
  '';
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;
  xdg.configHome = "${config.home.homeDirectory}/custom-config";
  programs.alistral = {
    enable = true;
    mutableSettings = true;
  };
  assertions = [
    {
      assertion = !(config.home.activation ? alistralImmutableSettings);
      message = "Inactive alistral settings must not create immutable cleanup.";
    }
  ];
  # The merge still runs, so settings removed last are removed, but without
  # a record it creates nothing.
  nmt.script = ''
    assertPathNotExists "home-files/custom-config/alistral/config.json"
    assertPathNotExists "home-files/Library/Application Support/alistral/config.json"
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
    chmod +x "$TMPDIR/activate"
    "$TMPDIR/activate"
    assertPathNotExists "$HOME"
  '';
}
