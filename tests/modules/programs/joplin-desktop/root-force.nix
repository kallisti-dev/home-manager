{
  config,
  lib,
  options,
  pkgs,
  ...
}:
{
  programs.joplin-desktop = {
    enable = true;
    sync.target = "dropbox";
    settings = lib.mkForce { };
  };
  test.asserts.warnings.expected = (import ./warnings.nix { inherit lib options; }) [
    [
      "sync"
      "target"
    ]
  ];
  nmt.script =
    assert config.programs.joplin-desktop.general.editor == null;
    ''
      generated="$(grep -o '/nix/store/[^ ]*-joplin-settings.json' $TESTED/activate)"
      ${pkgs.jq}/bin/jq -e '. == {}' "$generated" > /dev/null \
        || fail "Expected no settings, got $(cat "$generated")"
      assertPathNotExists home-files/.config/joplin-desktop/settings.json
    '';
}
