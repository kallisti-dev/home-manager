{
  enable,
  mutableSettings ? false,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-plex-mpv-shim-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.plexMpvShimSettingsActivation.data}
  '';
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  services.plex-mpv-shim = {
    inherit enable mutableSettings;
    settings = lib.optionalAttrs (!enable) { auto_play = true; };
  };

  nmt.script =
    assert (config.home.activation ? plexMpvShimSettingsActivation) == (enable && mutableSettings);
    assert !(config.home.activation ? plexMpvShimImmutableSettings);
    ''
      assertPathNotExists home-files/.config/plex-mpv-shim/conf.json
    ''
    + lib.optionalString enable ''
      assertFileNotRegex home-files/.config/systemd/user/plex-mpv-shim.service 'X-Restart-Triggers'
    ''
    + (
      if enable && mutableSettings then
        # The merge still runs, so settings removed last are removed, but
        # without a record it creates nothing.
        ''
          export HOME=$TMPDIR/hm-user
          substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
          chmod +x "$TMPDIR/activate"
          "$TMPDIR/activate"
          assertPathNotExists "$HOME/.config/plex-mpv-shim"
          assertPathNotExists "$HOME/.local/state"
        ''
      else
        ''
          assertFileNotRegex activate 'plexMpvShimSettingsActivation|plex-mpv-shim-conf.json'
        ''
    );
}
