{
  config,
  lib,
  pkgs,
  ...
}:

let
  mkActivation =
    name: configuration:
    pkgs.writeShellScript "activate-${name}" ''
      set -euo pipefail
      ${configuration.lib.bash.initHomeManagerLib}
      ${configuration.home.activation.activateJoplinDesktopConfig.data or ""}
    '';
  generations = lib.mapAttrs mkActivation (
    {
      first = config;
    }
    // lib.mapAttrs (_: specialisation: specialisation.configuration) config.specialisation
  );
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.joplin-desktop = {
    enable = true;
    settings = {
      "sync.target" = 7;
      "sync.interval" = 600;
      newNoteFocus = "title";
      "notes.perFolderSortOrders".inbox = {
        field = "title";
        reverse = false;
      };
      "ui.layout" = {
        key = "root";
        children = [
          {
            key = "sideBar";
            width = 250;
          }
        ];
      };
    };
  };

  specialisation = {
    dropped.configuration.programs.joplin-desktop.settings = lib.mkForce {
      "sync.target" = 7;
      "sync.interval" = null;
      newNoteFocus = "";
    };
    emptied.configuration.programs.joplin-desktop.settings = lib.mkForce { };
    disabled.configuration.programs.joplin-desktop.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    joplin=$HOME/.config/joplin-desktop/settings.json
    records=$XDG_STATE_HOME/home-manager/mutable-settings$HOME/.config/joplin-desktop
    activate() {
      substitute "$1" "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
    }
    assertJson() {
      ${lib.getExe pkgs.jaq} -e "$2" "$1" > /dev/null || fail "Expected $2 in $1, got $(cat "$1")"
    }
    edit() {
      ${lib.getExe pkgs.jaq} "$2" "$1" > "$TMPDIR/edited"
      cat "$TMPDIR/edited" > "$1"
    }

    activate ${generations.first}
    # What Joplin writes: every save adds `$schema`, and its settings are
    # objects it updates in place, such as the sort order of another folder
    # or the width of a resized panel.
    edit "$joplin" '
      ."$schema" = "https://joplinapp.org/schema/settings.json"
      | ."notes.perFolderSortOrders".archive = {field: "user_updated_time", reverse: true}
      | ."ui.layout".children[0].width = 300
    '

    # Settings go whole, as `+` replaces them, rather than leaving fragments.
    # Null and empty values count as removed.
    activate ${generations.dropped}
    assertJson "$joplin" '. == {
      "$schema": "https://joplinapp.org/schema/settings.json",
      "sync.target": 7,
      "ui.layout": {key: "root", children: [{key: "sideBar", width: 300}]}
    }'

    # Removing the last setting removes it too, and the record.
    activate ${generations.emptied}
    assertJson "$joplin" '. == {
      "$schema": "https://joplinapp.org/schema/settings.json",
      "ui.layout": {key: "root", children: [{key: "sideBar", width: 300}]}
    }'
    assertPathNotExists "$records/settings.json.json"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp "$joplin" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff "$TMPDIR/before-disabled" "$joplin" || fail "Disabling the module changed the file"
    activate ${generations.dropped}
    assertJson "$joplin" '. == {
      "$schema": "https://joplinapp.org/schema/settings.json",
      "sync.target": 7
    }'
  '';
}
