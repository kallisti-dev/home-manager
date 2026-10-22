{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkIf mkOption;

  cfg = config.programs.herdr;

  tomlFormat = pkgs.formats.toml { };
  generatedSettings = tomlFormat.generate "herdr-settings.toml" cfg.settings;
  # Match the merger's TOML serialization so unchanged mutable files can be
  # replaced by a store link when mutableSettings is disabled.
  settingsSource = pkgs.runCommand "herdr-config.toml" { } ''
    settings="$(${lib.getExe pkgs.jaq} --from toml --to toml '.' ${generatedSettings})"
    printf '%s\n' "$settings" > "$out"
  '';
  settingsPath = "${config.xdg.configHome}/herdr/config.toml";

  mutableSettingsActivation = lib.hm.generators.mkImpureConfigMerger {
    inherit pkgs;
    format = "toml";
    empty = "{}";
    jqOperation = "$dynamic * $static";
    path = settingsPath;
    staticSettings = settingsSource;
    mode = "600";
    removal.enable = config.home.mutableSettings.removeDropped;
  };

  herdrBin = if cfg.package == null then "herdr" else lib.escapeShellArg (lib.getExe cfg.package);
  reloadConfig = "${herdrBin} server reload-config || true";
in
{
  meta.maintainers = [ lib.maintainers.amadejkastelic ];

  options.programs.herdr = {
    enable = lib.mkEnableOption "Herdr";

    package = lib.mkPackageOption pkgs "herdr" { nullable = true; };

    mutableSettings = mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Whether to merge declared settings into a writable Herdr configuration
        file during activation, preserving settings added by Herdr or the user.
        Declared values, including arrays, take precedence. With
        [](#opt-home.mutableSettings.removeDropped), settings removed from the
        configuration are removed from the file unless Herdr has changed them
        since. Comments and formatting are not preserved. New files have mode
        0600; existing files retain their permissions.

        The default keeps the configuration file immutable. Switching back to
        immutable settings automatically replaces the writable file only when
        it is byte-identical to the declared settings. Changed files use Home
        Manager's normal collision and backup handling. Empty settings leave
        the file unmanaged.
      '';
    };

    settings = mkOption {
      inherit (tomlFormat) type;
      default = { };
      example = {
        onboarding = false;
        terminal = {
          default_shell = "nu";
          shell_mode = "auto";
          new_cwd = "follow";
        };
        theme = {
          name = "catppuccin";
          auto_switch = true;
          light_name = "catppuccin-latte";
          dark_name = "catppuccin";
        };
        ui = {
          sidebar_width = 32;
          agent_panel_sort = "priority";
          toast.delivery = "herdr";
          sound.enabled = true;
        };
        keys.prefix = "ctrl+b";
        keys.command = [
          {
            key = "prefix+l";
            type = "plugin_action";
            command = "example.layout.apply";
            description = "apply layout";
          }
        ];
      };
      description = ''
        Configuration written to {file}`$XDG_CONFIG_HOME/herdr/config.toml`.
        See <https://herdr.dev/docs/configuration/> for the full list of options.
      '';
    };
  };

  config = mkIf cfg.enable {
    home = {
      packages = mkIf (cfg.package != null) [ cfg.package ];

      # Reload only when the merge changed the file, like `onChange` does for
      # the linked file, as the merge also runs while no settings are declared.
      activation.herdrMutableSettings = lib.mkIf cfg.mutableSettings (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          (
            before="$(cat -- ${lib.escapeShellArg settingsPath} 2> /dev/null || true)"
            ${mutableSettingsActivation}
            if [[ "$(cat -- ${lib.escapeShellArg settingsPath} 2> /dev/null || true)" != "$before" ]]; then
              run ${reloadConfig}
            fi
          )
        ''
      );

      activation.herdrImmutableSettings = lib.mkIf (!cfg.mutableSettings && cfg.settings != { }) (
        lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] (
          lib.hm.generators.mkImpureConfigCleanup {
            file = config.xdg.configFile."herdr/config.toml";
          }
        )
      );
    };

    xdg.configFile."herdr/config.toml" = mkIf (!cfg.mutableSettings && cfg.settings != { }) {
      source = settingsSource;
      onChange = reloadConfig;
    };
  };
}
