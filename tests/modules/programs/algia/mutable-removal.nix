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
      ${configuration.home.activation.algiaMutableSettings.data or ""}
    '';
  generations = lib.mapAttrs mkActivation (
    {
      first = config;
    }
    // lib.mapAttrs (_: specialisation: specialisation.configuration) config.specialisation
  );
  keptRelay = {
    read = true;
    write = false;
    search = true;
  };
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.algia = {
    enable = true;
    package = null;
    mutableSettings = true;
    settings = {
      relays = {
        "wss://nix.example" = {
          read = true;
          write = true;
          search = false;
        };
        "wss://kept.example" = keptRelay;
      };
      followList = [
        "nix-a"
        "nix-b"
      ];
      privatekey = "nsec-declared";
      emojis.wave = "https://emoji.example/wave.png";
      delegation = {
        delegator = "delegator-pubkey";
        conditions = "kind=1&created_at>1&created_at<2";
        token = "nix-token";
      };
    };
  };

  specialisation = {
    dropped.configuration.programs.algia.settings = lib.mkForce {
      relays."wss://kept.example" = keptRelay;
      followList = [ "nix-b" ];
    };
    emptied.configuration.programs.algia.settings = lib.mkForce { };
    disabled.configuration.programs.algia.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    settings=$HOME/.config/algia/config.json
    record=$XDG_STATE_HOME/home-manager/mutable-settings$settings.json
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

    # Without a record, empty settings create nothing.
    activate ${generations.emptied}
    assertPathNotExists "$settings"
    assertPathNotExists "$record"

    # What algia writes: saving adds every relay flag and its own fields, a
    # refresh adds the published follows, and importing a renewed delegation
    # replaces the declared one.
    activate ${generations.first}
    edit "$settings" '
      .relays |= map_values(. + {global: false, dm: false, bm: false, auth: false})
      | .followList += ["app-c"]
      | .updated = "2026-10-21T00:00:00Z"
      | .["nwc-uri"] = ""
      | .["file-servers"] = null
      | .delegation.conditions = "kind=1&created_at>2&created_at<3"
      | .delegation.token = "renewed-token"
    '

    # A dropped relay goes whole, with the flags algia added, rather than
    # leaving a relay with every flag off. Dropped follows go and the rest
    # are still combined. The changed delegation and the key stay.
    activate ${generations.dropped}
    assertJson "$settings" '. == {
      relays: {"wss://kept.example": {
        read: true, write: false, search: true,
        global: false, dm: false, bm: false, auth: false
      }},
      followList: ["app-c", "nix-b"],
      privatekey: "nsec-declared",
      updated: "2026-10-21T00:00:00Z",
      "nwc-uri": "",
      "file-servers": null,
      delegation: {
        delegator: "delegator-pubkey",
        conditions: "kind=1&created_at>2&created_at<3",
        token: "renewed-token"
      }
    }'

    # Removing the last declarations removes them too, and the record. With
    # no relays left, algia falls back to its default relay.
    activate ${generations.emptied}
    assertJson "$settings" '
      (has("relays") | not)
      and .followList == ["app-c"]
      and .privatekey == "nsec-declared"
      and .delegation.token == "renewed-token"
    '
    assertPathNotExists "$record"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp "$settings" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    assertFileContent "$settings" "$TMPDIR/before-disabled"
    activate ${generations.dropped}
    assertJson "$settings" '
      (.relays | keys) == ["wss://kept.example"]
      and .followList == ["app-c", "nix-b"]
      and .privatekey == "nsec-declared"
      and (has("delegation") or has("emojis") | not)
    '
  '';
}
