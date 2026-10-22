{
  lib,
  pkgs,
  config,
  ...
}:

let
  configPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/andcli"
    else
      "${lib.removePrefix config.home.homeDirectory config.xdg.configHome}/andcli";
  file = config.home.file."${configPath}/config.yaml";
  cleanup = config.home.activation.andcliImmutableSettings;
in
{
  programs.andcli = {
    enable = true;
    package = null;
    settings = {
      options = {
        show_usernames = false;
        show_tokens = true;
      };
    };
  };

  xdg.configHome = "${config.home.homeDirectory}/custom-config";

  assertions = [
    {
      assertion = !config.programs.andcli.mutableSettings;
      message = "andcli settings must default to immutable settings.";
    }
    {
      assertion = !(config.home.activation ? andcliMutableSettings);
      message = "andcli settings must not create mutable activation.";
    }
    {
      assertion = cleanup.after == [ "writeBoundary" ] && cleanup.before == [ "linkGeneration" ];
      message = "andcli cleanup must run between writeBoundary and linkGeneration.";
    }
    {
      assertion =
        lib.hasInfix (lib.escapeShellArg file.target) cleanup.data
        && lib.hasInfix (lib.escapeShellArg (builtins.unsafeDiscardStringContext (toString file.source))) cleanup.data;
      message = "andcli cleanup must use the configured settings target and source.";
    }
  ];

  nmt.script = ''
    assertFileContent "home-files/${configPath}/config.yaml" \
      ${./config.yaml}
  '';
}
