{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-antigravity-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.antigravitySettings.data}
  '';
in
{
  programs.antigravity-cli = {
    enable = true;
    package = null;
    permissions = { };
    mutableSettings = true;
  };
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  assertions = [
    {
      assertion = !(config.home.activation ? antigravityImmutableSettings);
      message = "Empty Antigravity settings must not schedule cleanup.";
    }
  ];

  # The merges still run, so settings removed last are removed, but without
  # a record they create nothing.
  nmt.script = ''
    assertPathNotExists home-files/.gemini/antigravity-cli/settings.json
    assertPathNotExists home-files/.gemini/config/mcp_config.json
    export HOME=$TMPDIR/hm-user
    substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
    chmod +x "$TMPDIR/activate"
    "$TMPDIR/activate"
    assertPathNotExists "$HOME/.gemini"
    assertPathNotExists "$HOME/.local/state"
  '';
}
