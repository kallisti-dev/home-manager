{
  lib,
  config,
  pkgs,
  ...
}:
let
  mkVesktopLikeModule = import ./mkVesktopLikeModule.nix;
  cfg = config.programs.vesktop;
  fileDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/vesktop"
    else
      "${config.xdg.configHome}/vesktop";
  settingsFiles = [
    {
      name = "settings.json";
      inherit (cfg) settings;
      mutable = cfg.mutableSettings;
      removal.sets = [ [ "spellCheckLanguages" ] ];
    }
    {
      name = "settings/settings.json";
      settings = cfg.vencord.settings;
      mutable = cfg.vencord.mutableSettings;
      removal = {
        # Vencord reads a plugin entry without `enabled` as disabled, also for
        # plugins that are on by default, and some plugins keep data such as
        # text replacement rules in their entry, which must not go with it.
        keep = [
          [
            "plugins"
            "*"
            "enabled"
          ]
        ];
        sets = [
          [ "enabledThemes" ]
          [ "themeLinks" ]
        ];
      };
    }
  ];
  immutableConfigCleanup = lib.concatMapStrings (
    {
      name,
      settings,
      mutable,
      ...
    }:
    lib.optionalString (!mutable && settings != { }) (
      lib.hm.generators.mkImpureConfigCleanup {
        file = config.home.file."${fileDir}/${name}";
      }
    )
  ) settingsFiles;
  jsonFormat = pkgs.formats.json { };
  mutableSettingsOption = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Merge declarative settings into a writable JSON file during activation,
      preserving settings changed in the application. Declarative values take
      precedence; arrays are replaced rather than merged. Formatting is not
      preserved. Close Vesktop before activating to avoid concurrent writes.

      With [](#opt-home.mutableSettings.removeDropped), settings removed from
      the configuration are removed from the file unless the application has
      changed them since. A Vencord plugin keeps its `enabled` value, so a
      plugin removed from the configuration stays enabled or disabled, along
      with data stored in its entry; spellcheck languages and themes added in
      the application are kept.

      When disabled, files byte-identical to the generated configuration are
      replaced with managed symlinks. Other files use normal collision handling.
    '';
  };
in
{
  imports = [
    (mkVesktopLikeModule {
      moduleName = "vesktop";
      cordModuleName = "vencord";
      settingsLink = "https://github.com/Vencord/Vesktop/blob/main/src/shared/settings.d.ts";
      cordSettingsLink = "https://github.com/Vendicated/Vencord/blob/main/src/api/Settings.ts";
      installPackage = false;
      maintainers = with lib.maintainers; [
        Flameopathic
        LilleAila
      ];
    })
  ];

  options.programs.vesktop = {
    mutableSettings = mutableSettingsOption;
    vencord.mutableSettings = mutableSettingsOption;
    vencord.useSystem = lib.mkEnableOption "Vencord package from Nixpkgs";
  };

  config = lib.mkIf cfg.enable {
    home = {
      file = lib.mkMerge (
        map (
          {
            name,
            settings,
            mutable,
            ...
          }:
          lib.mkIf (mutable && settings != { }) {
            "${fileDir}/${name}".enable = false;
          }
        ) settingsFiles
      );

      activation = {
        vesktopSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.concatMapStrings (
            {
              name,
              settings,
              mutable,
              removal,
            }:
            lib.optionalString mutable (
              lib.hm.generators.mkImpureConfigMerger {
                inherit pkgs;
                format = "json";
                empty = "{}";
                jqOperation = "$dynamic * $static";
                path =
                  let
                    # The file entry, which may set another target, exists
                    # only while settings are declared.
                    target = config.home.file."${fileDir}/${name}".target or "${fileDir}/${name}";
                  in
                  if lib.hasPrefix "/" target then target else "${config.home.homeDirectory}/${target}";
                staticSettings = jsonFormat.generate "vesktop-${baseNameOf name}" settings;
                mode = "600";
                removal = removal // {
                  enable = config.home.mutableSettings.removeDropped;
                };
              }
            )
          ) settingsFiles
        );

        vesktopImmutableSettings = lib.mkIf (immutableConfigCleanup != "") (
          lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] immutableConfigCleanup
        );
      };

      packages = lib.mkIf (cfg.package != null) [
        (cfg.package.override { withSystemVencord = cfg.vencord.useSystem; })
      ];
    };

  };
}
