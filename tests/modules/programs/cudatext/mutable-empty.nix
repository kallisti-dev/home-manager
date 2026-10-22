{
  config,
  lib,
  pkgs,
  ...
}:
let
  activation = pkgs.writeShellScript "activate-cudatext-settings" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.cudatextSettings.data}
  '';
  configDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/CudaText"
    else
      ".config/cudatext";
in
{
  programs.cudatext = {
    enable = true;
    package = null;
    mutableSettings = true;
  };
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  assertions = [
    {
      assertion = config.programs.cudatext.mutableSettings;
      message = "Mutable CudaText settings must remain enabled for an empty configuration.";
    }
    {
      assertion = !(config.home.activation ? cudatextImmutableSettings);
      message = "Empty CudaText settings must not register immutable settings cleanup.";
    }
  ];

  # The merge still runs, so settings removed last are removed, but without
  # a record it creates nothing.
  nmt.script = ''
    assertPathNotExists "home-files/${configDir}/settings/user.json"
    export HOME=$TMPDIR/hm-user
    substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
    chmod +x "$TMPDIR/activate"
    "$TMPDIR/activate"
    assertPathNotExists "$HOME/${configDir}"
    assertPathNotExists "$HOME/.local/state"
  '';
}
