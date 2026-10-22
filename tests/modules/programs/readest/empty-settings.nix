{
  config,
  lib,
  pkgs,
  ...
}:

let
  activation = pkgs.writeShellScript "activate-readest" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.readestSettings.data}
  '';
in
{
  programs.readest = {
    enable = true;
    package = config.lib.test.mkStubPackage { name = "readest"; };
  };

  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  # The merge still runs, so settings removed last are removed, but without
  # a record it creates nothing.
  nmt.script = ''
    assertPathNotExists home-files/.config/com.bilingify.readest/settings.json
    export HOME=$TMPDIR/hm-user
    substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
    chmod +x "$TMPDIR/activate"
    "$TMPDIR/activate"
    assertPathNotExists "$HOME/.config"
    assertPathNotExists "$HOME/.local/state"
  '';
}
