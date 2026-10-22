{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.readest;
  jsonFormat = pkgs.formats.json { };

  inherit (lib)
    mkEnableOption
    mkPackageOption
    mkOption
    mkIf
    ;
in
{
  meta.maintainers = [ lib.maintainers.nyxar77 ];
  options.programs.readest = {
    enable = mkEnableOption "Readest";
    package = mkPackageOption pkgs "readest" { nullable = true; };

    settings = mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        telemetryEnabled = false;
        libraryViewMode = "grid";
        globalViewSettings = {
          theme = "dark";
          defaultFontSize = 18;
          lineHeight = 1.5;
        };
      };
      description = ''
        Readest preferences to merge into
        {file}`$XDG_CONFIG_HOME/com.bilingify.readest/settings.json`.

        Readest owns this file and may add or update values while it is
        running. Values declared here take precedence on Home Manager
        activation, while values Readest adds are preserved. With
        [](#opt-home.mutableSettings.removeDropped), settings removed from the
        configuration are removed from the file unless Readest has changed
        them since. Fields of nested settings that Readest does not fill in
        with defaults, such as those of `kosync`, stay in the file.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = mkIf (cfg.package != null) [ cfg.package ];

    home.activation.readestSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (
      lib.hm.generators.mkImpureConfigMerger {
        inherit pkgs;
        format = "json";
        empty = "{}";
        jqOperation = "$dynamic * $static";
        path = "${config.xdg.configHome}/com.bilingify.readest/settings.json";
        staticSettings = jsonFormat.generate "readest-settings.json" cfg.settings;
        mode = "600";
        removal = {
          enable = config.home.mutableSettings.removeDropped;
          # Readest fills in defaults for top-level keys and for the fields of
          # globalReadSettings, globalViewSettings and aiSettings, but not for
          # the fields of these objects, which would read as undefined once
          # removed.
          keep =
            map
              (key: [
                key
                "*"
              ])
              [
                "hardwarePageTurner"
                "dictionarySettings"
                "kosync"
                "bookorbit"
                "readwise"
                "hardcover"
                "pagebound"
                "notion"
                "webdav"
                "googleDrive"
                "s3"
                "onedrive"
                "icloud"
                "syncCategories"
              ]
            ++ [
              [
                "globalReadSettings"
                "customHighlightColors"
                "*"
              ]
              [
                "globalReadSettings"
                "highlightStyles"
                "*"
              ]
              [
                "globalViewSettings"
                "paragraphMode"
                "*"
              ]
              [
                "globalViewSettings"
                "ttsHighlightOptions"
                "*"
              ]
              [
                "globalViewSettings"
                "noteExportConfig"
                "*"
              ]
              [
                "aiSettings"
                "reedy"
                "*"
              ]
            ];
          # Readest adds fields such as `contentId` to the catalogs it saves,
          # and cannot use a catalog or theme without its declared fields.
          maps = [
            {
              path = [ "opdsCatalogs" ];
              keys = [ "id" ];
              atomic = true;
            }
            {
              path = [
                "globalReadSettings"
                "customThemes"
              ];
              keys = [ "name" ];
              atomic = true;
            }
          ];
        };
      }
    );
  };
}
