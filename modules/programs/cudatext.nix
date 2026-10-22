{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    types
    mkIf
    mkEnableOption
    mkPackageOption
    mkOption
    nameValuePair
    mapAttrs'
    ;

  cfg = config.programs.cudatext;

  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.cudatext = {
    enable = mkEnableOption "cudatext";
    package = mkPackageOption pkgs "cudatext" { nullable = true; };
    mutableSettings = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to merge declared user settings, hotkeys and lexer settings
        into writable files during activation. Existing comments and trailing
        commas are accepted, but comments and formatting are lost when writing
        JSON. Declared values, including arrays, take precedence. Switching back
        to immutable settings only removes byte-identical files; changed files
        require backup or removal.

        With [](#opt-home.mutableSettings.removeDropped), settings removed from
        the configuration are removed from the files unless CudaText has
        changed them since. Hotkey entries are removed whole, with what
        CudaText added to them, or kept whole if a declared value changed.
        Removing a lexer from [](#opt-programs.cudatext.lexerSettings) or
        [](#opt-programs.cudatext.lexerHotkeys) leaves its file as it is; set
        the lexer to `{ }` first to remove its settings.
      '';
    };

    hotkeys = mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        "2823" = {
          name = "code tree: clear filter";
          s1 = [ "Home" ];
        };

        "153" = {
          name = "delete char right (delete)";
          s1 = [ "End" ];
        };

        "655465" = {
          name = "caret to line end";
          s1 = [ ];
        };

        "116" = {
          name = "column select: page up";
          s1 = [ ];
        };

        "655464" = {
          name = "caret to line begin";
          s1 = [ ];
        };
      };
      description = ''
        Hotkeys for Cudatext. To see the available options, change
        the settings in the dialog "Help | Command palette" and
        look at the changes in `settings/keys.json`.
      '';
    };

    userSettings = mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        numbers_style = 2;
        numbers_center = false;
        numbers_for_carets = true;
      };
      description = ''
        User configuration for Cudatext.
      '';
    };

    lexerSettings = mkOption {
      type = types.attrsOf jsonFormat.type;
      default = { };
      example = {
        C = {
          numbers_style = 2;
        };
        Python = {
          numbers_style = 1;
          numbers_center = false;
        };
        Rust = {
          numbers_style = 2;
          numbers_center = false;
          numbers_for_carets = true;
        };
      };
      description = ''
        User configuration settings specific to each lexer.
      '';
    };

    lexerHotkeys = mkOption {
      type = types.attrsOf jsonFormat.type;
      default = { };
      example = {
        C = {
          "153" = {
            name = "delete char right (delete)";
            s1 = [ "End" ];
          };

          "655465" = {
            name = "caret to line end";
            s1 = [ ];
          };
        };

        Python = {
          "2823" = {
            name = "code tree: clear filter";
            s1 = [ "Home" ];
          };

          "655464" = {
            name = "caret to line begin";
            s1 = [ ];
          };
        };
      };
      description = ''
        Hotkeys settings specific to each lexer.
      '';
    };
  };

  config =
    let
      settingsPath =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "Library/Application Support/CudaText/settings"
        else
          "${lib.removePrefix config.home.homeDirectory config.xdg.configHome}/cudatext/settings";
      settingsFiles = {
        "${settingsPath}/keys.json".source = jsonFormat.generate "cudatext-keys.json" cfg.hotkeys;
        "${settingsPath}/user.json".source = jsonFormat.generate "cudatext-user.json" cfg.userSettings;
      }
      // (mapAttrs' (
        k: v:
        nameValuePair "${settingsPath}/lexer ${k}.json" {
          source = jsonFormat.generate "cudatext-lexer-${k}" v;
        }
      ) cfg.lexerSettings)
      // (mapAttrs' (
        k: v:
        nameValuePair "${settingsPath}/keys lexer ${k}.json" {
          source = jsonFormat.generate "cudatext-lexer-keys-${k}" v;
        }
      ) cfg.lexerHotkeys);
      # Hotkeys and user settings are linked only when declared, but merged
      # even when empty, so that removing the last one removes it.
      linkedFiles = removeAttrs settingsFiles (
        lib.optional (cfg.hotkeys == { }) "${settingsPath}/keys.json"
        ++ lib.optional (cfg.userSettings == { }) "${settingsPath}/user.json"
      );
      json5 = pkgs.python3Packages.toPythonApplication pkgs.python3Packages.json5;
      settingsDirectory =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "${config.home.homeDirectory}/Library/Application Support/CudaText/settings"
        else
          "${config.xdg.configHome}/cudatext/settings";
    in
    mkIf cfg.enable {
      home = {
        packages = mkIf (cfg.package != null) [ cfg.package ];

        file = mkIf (!cfg.mutableSettings) linkedFiles;

        activation = {
          cudatextSettings = mkIf cfg.mutableSettings (
            lib.hm.dag.entryAfter [ "linkGeneration" ] (
              lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  name: file:
                  lib.hm.generators.mkImpureConfigMerger {
                    inherit pkgs;
                    format = "json";
                    empty = "{}";
                    jqOperation = ''if ($dynamic | type) == "object" and ($static | type) == "object" then $dynamic * $static else error("expected JSON objects") end'';
                    path = "${settingsDirectory}/${lib.removePrefix "${settingsPath}/" name}";
                    staticSettings = file.source;
                    reader = "${lib.getExe json5} --as-json";
                    removal = {
                      enable = config.home.mutableSettings.removeDropped;
                      # CudaText unbinds a command whose entry lacks `s1`, so
                      # entries in the hotkey files are removed or kept whole.
                      atomic = lib.optional (lib.hasPrefix "keys" (baseNameOf name)) [ "*" ];
                    };
                  }
                ) settingsFiles
              )
            )
          );
          cudatextImmutableSettings = mkIf (!cfg.mutableSettings && linkedFiles != { }) (
            lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] (
              lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  name: _: lib.hm.generators.mkImpureConfigCleanup { file = config.home.file.${name}; }
                ) linkedFiles
              )
            )
          );
        };
      };
    };
}
