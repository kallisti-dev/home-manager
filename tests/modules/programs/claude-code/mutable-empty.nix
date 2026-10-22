{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-claude-code-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.claudeCodeSettings.data}
  '';
in
{
  programs.claude-code = {
    enable = true;
    package = null;
    mutableSettings = true;
  };
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  assertions = [
    {
      assertion = config.programs.claude-code.mutableSettings;
      message = "Mutable Claude Code settings must remain enabled for an empty configuration.";
    }
  ];

  # The merge still runs, so settings removed last are removed, but without
  # a record it creates nothing.
  nmt.script = ''
    assertPathNotExists "home-files/.claude/settings.json"
    assertPathNotExists "home-files/.claude/plugins/known_marketplaces.json"
    export HOME=$TMPDIR/hm-user
    substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
    chmod +x "$TMPDIR/activate"
    "$TMPDIR/activate"
    assertPathNotExists "$HOME/.claude"
    assertPathNotExists "$HOME/.local/state"
  '';
}
