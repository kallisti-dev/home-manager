{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-andcli-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.andcliMutableSettings.data}
  '';
in
{
  programs.andcli = {
    enable = lib.mkDefault true;
    mutableSettings = lib.mkDefault true;
    package = null;
  };
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;
  xdg.configHome = "${config.home.homeDirectory}/custom-config";

  assertions = [
    {
      assertion = !(config.home.activation ? andcliImmutableSettings);
      message = "andcli empty-settings must not create immutable cleanup.";
    }
  ];

  # The merge still runs, so settings removed last are removed, but without
  # a record it creates nothing.
  nmt.script = ''
    assertPathNotExists "home-files/custom-config/andcli/config.yaml"
    assertPathNotExists "home-files/Library/Application Support/andcli/config.yaml"
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
    chmod +x "$TMPDIR/activate"
    "$TMPDIR/activate"
    assertPathNotExists "$HOME"
  '';
}
