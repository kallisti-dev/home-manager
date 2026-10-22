{
  config,
  lib,
  pkgs,
  ...
}:
let

  jsonFormat = pkgs.formats.json { };
  cfg = config.services.plex-mpv-shim;
  settingsFile = jsonFormat.generate "plex-mpv-shim-conf.json" cfg.settings;
  # The cleanup reads the linked file entry, so both must use this condition.
  linkSettings = !cfg.mutableSettings && cfg.settings != { };

in
{
  meta.maintainers = [ lib.maintainers.starcraft66 ];

  options = {
    services.plex-mpv-shim = {
      enable = lib.mkEnableOption "Plex mpv shim";

      package = lib.mkPackageOption pkgs "plex-mpv-shim" { };

      settings = lib.mkOption {
        inherit (jsonFormat) type;
        default = { };
        example = {
          adaptive_transcode = false;
          allow_http = false;
          always_transcode = false;
          audio_ac3passthrough = false;
          audio_dtspassthrough = false;
          auto_play = true;
          auto_transcode = true;
        };
        description = ''
          Configuration written to
          {file}`$XDG_CONFIG_HOME/plex-mpv-shim/conf.json`. See
          [](#opt-services.plex-mpv-shim.mutableSettings) for how the file is
          managed, and
          <https://github.com/iwalton3/plex-mpv-shim/blob/master/README.md>
          for the configuration documentation.
        '';
      };

      mutableSettings = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Whether to merge [](#opt-services.plex-mpv-shim.settings) into a
          writable {file}`conf.json` at activation instead of linking it from
          the Nix store.

          Plex mpv shim writes this file when it loads settings and whenever a
          setting is changed from its menu or a Plex remote. With a linked file
          those writes fail, and the generated player identity
          (`client_uuid`) is not kept across restarts.

          When enabled, declared settings override existing values and other
          keys are preserved. With [](#opt-home.mutableSettings.removeDropped),
          settings removed from the configuration are removed from the file
          unless Plex mpv shim has changed them since. Changed settings trigger
          a restart when automatic systemd service switching is enabled. If
          {option}`systemd.user.startServices` is `false` or `"suggest"`, restart
          the shim manually to load changed settings. A running shim can still
          write its old values back between the merge and restart; stop it
          before switching and start it afterward to avoid this window.

          Disabling this option later leaves the writable {file}`conf.json` in
          place unless it is identical to the generated one. If settings are
          nonempty, move or remove it before switching, or Home Manager reports
          a file collision.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "services.plex-mpv-shim" pkgs lib.platforms.linux)
    ];

    xdg.configFile."plex-mpv-shim/conf.json" = lib.mkIf linkSettings {
      source = settingsFile;
    };

    home.activation.plexMpvShimImmutableSettings = lib.mkIf linkSettings (
      lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] (
        lib.hm.generators.mkImpureConfigCleanup {
          file = config.xdg.configFile."plex-mpv-shim/conf.json";
        }
      )
    );

    # Merge before reloadSystemd so the restart below reads the result.
    home.activation.plexMpvShimSettingsActivation = lib.mkIf cfg.mutableSettings (
      lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ] (
        lib.hm.generators.mkImpureConfigMerger {
          inherit pkgs;
          format = "json";
          empty = "{}";
          jqOperation = "$dynamic * $static";
          path = "${config.xdg.configHome}/plex-mpv-shim/conf.json";
          staticSettings = settingsFile;
          removal.enable = config.home.mutableSettings.removeDropped;
        }
      )
    );

    systemd.user.services.plex-mpv-shim = {
      Unit = {
        Description = "Plex mpv shim";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        X-Restart-Triggers = lib.mkIf (cfg.mutableSettings && cfg.settings != { }) [
          "${settingsFile}"
        ];
      };

      Service = {
        ExecStart = "${cfg.package}/bin/plex-mpv-shim";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
