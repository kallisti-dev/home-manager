{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-jellyfin-mpv-shim-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.jellyfinMpvShimSettingsActivation.data}
  '';
in
{
  services.jellyfin-mpv-shim.enable = true;
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  # The merge still runs, so settings removed last are removed, but without
  # a record it creates nothing.
  nmt.script =
    assert config.systemd.user.services.jellyfin-mpv-shim.Unit.X-Restart-Triggers == [ ];
    ''
      assertPathNotExists home-files/.config/jellyfin-mpv-shim
      export HOME=$TMPDIR/hm-user
      substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
      assertPathNotExists "$HOME/.config/jellyfin-mpv-shim"
      assertPathNotExists "$HOME/.local/state"
    '';
}
