{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkPackageOption
    mkOption
    ;

  cfg = config.programs.algia;
  jsonFormat = pkgs.formats.json { };
  configPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/.config/algia/config.json"
    else
      "${config.xdg.configHome}/algia/config.json";
  configDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      ".config/algia"
    else
      "${lib.removePrefix config.home.homeDirectory config.xdg.configHome}/algia";

in
{
  options.programs.algia = {
    enable = mkEnableOption "algia";
    package = mkPackageOption pkgs "algia" { nullable = true; };
    mutableSettings = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Merge declarative settings into a writable configuration file during
        activation, preserving settings and credentials written by the application.
        Declarative values take precedence. Arrays are replaced, except that
        `followList` entries are combined and deduplicated.

        With [](#opt-home.mutableSettings.removeDropped), settings removed from
        the configuration are removed from the file unless algia has changed
        them since. Relays and the `delegation` are removed whole, with what
        algia added to them, or kept whole if a declared value changed;
        `privatekey` is never removed.

        Formatting is not preserved. Keep secrets out of {option}`settings`,
        since its values are still copied to the world-readable Nix store.
        New files have mode 0600; existing files retain their permissions.
      '';
    };

    settings = mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        relays = {
          "wss =//relay-jp.nostr.wirednet.jp" = {
            read = true;
            write = true;
            search = false;
          };
        };
      };
      description = ''
        Configuration settings for algia. All the available options can be found here:
        <https://github.com/mattn/algia?tab=readme-ov-file#configuration>

        The generated {file}`config.json` is written to the world-readable
        Nix store, so other local users can read a `privatekey` set here. If
        you need to set a private key, consider leaving this option empty
        and managing {file}`config.json` outside Home Manager, or enable
        {option}`mutableSettings` and add the key to the writable file
        yourself; the merge keeps it.
      '';
    };
  };

  config = mkIf cfg.enable {
    home = {
      activation = {
        algiaMutableSettings = lib.mkIf cfg.mutableSettings (
          lib.hm.dag.entryAfter [ "linkGeneration" ] (
            lib.hm.generators.mkImpureConfigMerger {
              inherit pkgs;
              format = "json";
              empty = "{}";
              jqOperation = ''
                ($dynamic * $static)
                | if (($static.followList | type) == "array") then
                    .followList = ((($dynamic.followList // []) + $static.followList) | unique)
                  else
                    .
                  end
              '';
              path = configPath;
              staticSettings = jsonFormat.generate "algia-mutable-settings" cfg.settings;
              mode = "600";
              removal = {
                enable = config.home.mutableSettings.removeDropped;
                # A relay left with only the flags algia added is never used,
                # yet stops algia from falling back to its default relay. A
                # delegation is invalid without any of its declared values.
                atomic = [
                  [
                    "relays"
                    "*"
                  ]
                  [ "delegation" ]
                ];
                # The settings description suggests moving the key into the
                # writable file, which removing its declaration must not undo.
                keep = [ [ "privatekey" ] ];
                sets = [ [ "followList" ] ];
              };
            }
          )
        );

        algiaImmutableSettings = lib.mkIf (!cfg.mutableSettings && cfg.settings != { }) (
          lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] (
            lib.hm.generators.mkImpureConfigCleanup {
              file = config.home.file."${configDir}/config.json";
            }
          )
        );
      };

      packages = mkIf (cfg.package != null) [ cfg.package ];

      file."${configDir}/config.json" = mkIf (!cfg.mutableSettings && cfg.settings != { }) {
        source = jsonFormat.generate "algia-config.json" cfg.settings;
      };
    };

  };
}
