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
      ${configuration.home.activation.plexMpvShimSettingsActivation.data or ""}
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

  services.plex-mpv-shim = {
    enable = true;
    mutableSettings = true;
    settings = {
      player_name = "Home Manager";
      auto_play = false;
      adaptive_transcode = true;
    };
  };

  specialisation = {
    dropped.configuration.services.plex-mpv-shim.settings = lib.mkForce {
      player_name = "Home Manager";
    };
    emptied.configuration.services.plex-mpv-shim.settings = lib.mkForce { };
    immutable.configuration.services.plex-mpv-shim.mutableSettings = lib.mkForce false;
    disabled.configuration.services.plex-mpv-shim.enable = lib.mkForce false;
  };

  nmt.script =
    let
      cleanup =
        config.specialisation.immutable.configuration.home.activation.plexMpvShimImmutableSettings.data;
    in
    # Switching back to immutable settings cleans up the merged file.
    assert lib.hasInfix "mutable-settings" cleanup && lib.hasInfix "plex-mpv-shim/conf.json" cleanup;
    ''
      export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
      conf=$HOME/.config/plex-mpv-shim/conf.json
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
      # those missing; from its menu, the changed setting.
      edit "$conf" '.client_uuid = "generated" | .always_transcode = false | .auto_play = true'

      # A dropped setting is removed unless the shim changed it.
      activate ${generations.dropped}
      assertJson "$conf" '. == {
        player_name: "Home Manager",
        auto_play: true,
        client_uuid: "generated",
        always_transcode: false
      }'

      # Removing the last setting removes it too, and the record.
      activate ${generations.emptied}
      assertJson "$conf" '. == {auto_play: true, client_uuid: "generated", always_transcode: false}'
      assertPathNotExists "$record"

      # Disabling the module changes nothing. Enabling it again removes what
      # was dropped meanwhile, as the record still describes the last merge.
      activate ${generations.first}
      cp "$conf" "$TMPDIR/before-disabled"
      activate ${generations.disabled}
      diff "$TMPDIR/before-disabled" "$conf" || fail "Disabling the module changed the file"
      activate ${generations.dropped}
      assertJson "$conf" '. == {player_name: "Home Manager", client_uuid: "generated", always_transcode: false}'
    '';
}
