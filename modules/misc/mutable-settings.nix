{ config, lib, ... }:

{
  options.home.mutableSettings.removeDropped = lib.mkOption {
    type = lib.types.bool;
    default = lib.versionAtLeast config.home.stateVersion "26.11";
    defaultText = lib.literalExpression ''lib.versionAtLeast config.home.stateVersion "26.11"'';
    example = true;
    description = ''
      Whether to remove a setting from a mutable settings file when it is
      removed from the configuration.

      Some modules merge declared settings into a file that the application
      can also change, instead of linking a read-only file from the Nix store,
      for example with [](#opt-programs.zed-editor.mutableUserSettings) or
      [](#opt-programs.claude-code.mutableSettings). After each merge, Home
      Manager records the settings it applied under
      {file}`$XDG_STATE_HOME/home-manager/mutable-settings`. With this option
      enabled, the next activation removes recorded settings that are no
      longer declared, unless the application or the user has changed them
      since. Settings that the application added itself are kept.

      Settings removed while this option is disabled stay in the file, also
      after it is enabled. Disabling a module leaves its settings in the file;
      removing the module's last setting while it is enabled removes them.
    '';
  };
}
