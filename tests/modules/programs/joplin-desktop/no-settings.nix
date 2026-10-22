{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-joplin-desktop" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.activateJoplinDesktopConfig.data}
  '';
in
{
  programs.joplin-desktop.enable = true;
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  # The merge still runs, so settings removed last are removed, but without
  # a record it creates nothing.
  nmt.script =
    assert builtins.elem config.programs.joplin-desktop.package config.home.packages;
    ''
      assertPathNotExists home-files/.config/joplin-desktop/settings.json
      export HOME=$TMPDIR/hm-user
      substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
      assertPathNotExists "$HOME/.config"
      assertPathNotExists "$HOME/.local/state"
    '';
}
