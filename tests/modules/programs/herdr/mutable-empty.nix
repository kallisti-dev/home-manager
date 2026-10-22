{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-herdr-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.herdrMutableSettings.data}
  '';
in
{
  programs.herdr = {
    enable = true;
    package = pkgs.writeShellScriptBin "herdr" ''
      echo "$*" >> "$HERDR_LOG"
    '';
    mutableSettings = true;
  };
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  assertions = [
    {
      assertion = !(config.home.activation ? herdrImmutableSettings);
      message = "Empty Herdr settings must not register immutable cleanup.";
    }
  ];

  test.asserts.warnings.expected = [ ];

  # The merge still runs, so settings removed last are removed, but without
  # a record it neither creates the file nor reloads Herdr.
  nmt.script = ''
    assertPathNotExists "home-files/.config/herdr/config.toml"
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    export HERDR_LOG=$TMPDIR/herdr.log
    substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
    chmod +x "$TMPDIR/activate"
    "$TMPDIR/activate"
    assertPathNotExists "$HOME"
    assertPathNotExists "$HERDR_LOG"
  '';
}
