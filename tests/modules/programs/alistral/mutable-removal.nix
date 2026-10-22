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
      ${configuration.home.activation.alistralMutableSettings.data or ""}
    '';
  generations = lib.mapAttrs mkActivation (
    {
      first = config;
    }
    // lib.mapAttrs (_: specialisation: specialisation.configuration) config.specialisation
  );
  configDir = if pkgs.stdenv.hostPlatform.isDarwin then "Library/Application Support" else ".config";
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.alistral = {
    enable = true;
    package = null;
    mutableSettings = true;
    settings = {
      default_user = "nix-user";
      tokens.nix-user = "nix-token";
      musicbrainz_server = {
        use_https = true;
        authority = "musicbrainz.org";
        ratelimit = {
          tokens = 10;
          each = 10;
        };
      };
      interzic.subsonic_clients = [
        {
          name = "home";
          url = "https://home.example";
          username = "nix-user";
          password = "home-password";
        }
        {
          name = "work";
          url = "https://work.example";
          username = "nix-user";
          password = "work-password";
        }
      ];
      mapper.backlisted = [
        "msid-a"
        "msid-b"
      ];
    };
  };

  specialisation = {
    dropped.configuration.programs.alistral.settings = lib.mkForce {
      default_user = "nix-user";
      musicbrainz_server = {
        use_https = true;
        authority = "musicbrainz.org";
      };
    };
    emptied.configuration.programs.alistral.settings = lib.mkForce { };
    disabled.configuration.programs.alistral.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    settings="$HOME/${configDir}/alistral/config.json"
    record="$XDG_STATE_HOME/home-manager/mutable-settings$settings.json"
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

    # What alistral writes: saving adds unset optional fields as null, and
    # `interzic add-subsonic` and the blacklist command append entries. The
    # changed password stands for an edit to a declared client.
    activate ${generations.first}
    edit "$settings" '
      .musicbrainz_server.ratelimit.max_burst = null
      | .musicbrainz_url = null
      | .interzic.subsonic_clients |= map(.strict_mbid = null)
      | .interzic.subsonic_clients[1].password = "changed"
      | .interzic.subsonic_clients += [{
          name: "mine",
          url: "https://mine.example",
          username: "me",
          password: "mine-password",
          strict_mbid: false
        }]
      | .mapper.backlisted += ["msid-app"]
    '

    # Dropped entries go whole, with the nulls alistral added, or stay whole
    # if changed, rather than leaving entries alistral cannot load. `tokens`
    # stays without its last token.
    activate ${generations.dropped}
    assertJson "$settings" '. == {
      default_user: "nix-user",
      tokens: {},
      musicbrainz_server: {use_https: true, authority: "musicbrainz.org"},
      musicbrainz_url: null,
      interzic: {subsonic_clients: [
        {name: "work", url: "https://work.example", username: "nix-user", password: "changed", strict_mbid: null},
        {name: "mine", url: "https://mine.example", username: "me", password: "mine-password", strict_mbid: false}
      ]},
      mapper: {backlisted: ["msid-app"]}
    }'

    # Removing the last declarations removes them too, and the record, also
    # once alistral has saved the server's missing rate limit as null.
    edit "$settings" '.musicbrainz_server.ratelimit = null'
    activate ${generations.emptied}
    assertJson "$settings" '
      (keys == ["interzic", "mapper", "musicbrainz_url", "tokens"])
      and .tokens == {}
      and (.interzic.subsonic_clients | map(.name)) == ["work", "mine"]
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
      .tokens == {}
      and .musicbrainz_server == {use_https: true, authority: "musicbrainz.org"}
      and (has("interzic") or has("mapper") | not)
    '
  '';
}
