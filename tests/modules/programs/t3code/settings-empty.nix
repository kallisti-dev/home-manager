{
  config,
  lib,
  pkgs,
  ...
}:

let
  activation = pkgs.writeShellScript "activate-t3code" ''
    set -euo pipefail
    ${config.lib.bash.initHomeManagerLib}
    ${config.home.activation.t3codeSettingsActivation.data}
    ${config.home.activation.t3codeKeybindingsActivation.data}
    ${config.home.activation.t3codeClientSettingsActivation.data}
  '';
in
{
  programs.t3code = {
    enable = true;
    package = config.lib.test.mkStubPackage { };
  };

  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  # The merges still run, so settings removed last are removed, but without
  # records they create nothing.
  nmt.script =
    assert !(config.home.activation ? t3codeImmutableConfig);
    ''
      assertPathNotExists "home-files/.t3/userdata/settings.json"
      assertPathNotExists "home-files/.t3/userdata/keybindings.json"
      assertPathNotExists "home-files/.t3/userdata/client-settings.json"
      export HOME=$TMPDIR/hm-user
      substitute ${activation} "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
      assertPathNotExists "$HOME/.t3"
      assertPathNotExists "$HOME/.local/state"
    '';
}
