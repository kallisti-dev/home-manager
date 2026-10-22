{ config, ... }:
{
  services.plex-mpv-shim = {
    enable = true;
    settings = {
      allow_http = false;
      auto_play = true;
      player_name = "Home Manager";
    };
  };

  nmt.script =
    assert !(config.home.activation ? plexMpvShimSettingsActivation);
    assert config.home.activation ? plexMpvShimImmutableSettings;
    ''
      assertFileContent home-files/.config/plex-mpv-shim/conf.json ${./basic-configuration.json}
      assertFileNotRegex activate 'Merging Nix-generated config'
      assertFileNotRegex home-files/.config/systemd/user/plex-mpv-shim.service 'X-Restart-Triggers'
    '';
}
