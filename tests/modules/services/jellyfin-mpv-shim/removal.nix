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
      ${configuration.home.activation.jellyfinMpvShimSettingsActivation.data or ""}
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

  services.jellyfin-mpv-shim = {
    enable = true;
    settings = {
      config_version = 5;
      player_name = "Home Manager";
      fullscreen = true;
      always_transcode = false;
    };
  };

  specialisation = {
    dropped.configuration.services.jellyfin-mpv-shim.settings = lib.mkForce {
      player_name = "Home Manager";
    };
    emptied.configuration.services.jellyfin-mpv-shim.settings = lib.mkForce { };
    disabled.configuration.services.jellyfin-mpv-shim.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    conf=$HOME/.config/jellyfin-mpv-shim/conf.json
    record=$XDG_STATE_HOME/home-manager/mutable-settings$conf.json
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
    # What the shim writes: on loading, every setting, with defaults for
    # those missing; from its settings menu, the changed setting.
    edit "$conf" '.client_uuid = "generated" | .auto_play = true | .fullscreen = false'

    # A dropped setting is removed unless the shim changed it, except for
    # config_version.
    activate ${generations.dropped}
    assertJson "$conf" '. == {
      config_version: 5,
      player_name: "Home Manager",
      fullscreen: false,
      client_uuid: "generated",
      auto_play: true
    }'

    # Removing the last setting removes it too, and the record.
    activate ${generations.emptied}
    assertJson "$conf" '. == {config_version: 5, fullscreen: false, client_uuid: "generated", auto_play: true}'
    assertPathNotExists "$record"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp "$conf" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff "$TMPDIR/before-disabled" "$conf" || fail "Disabling the module changed the file"
    activate ${generations.dropped}
    assertJson "$conf" '. == {config_version: 5, player_name: "Home Manager", client_uuid: "generated", auto_play: true}'
  '';
}
