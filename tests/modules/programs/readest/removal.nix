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
      ${configuration.home.activation.readestSettings.data or ""}
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

  programs.readest = {
    enable = true;
    package = config.lib.test.mkStubPackage { name = "readest"; };
    settings = {
      telemetryEnabled = false;
      libraryViewMode = "list";
      globalViewSettings = {
        theme = "dark";
        noteExportConfig.includeTitle = false;
      };
      kosync = {
        enabled = true;
        serverUrl = "https://sync.example.org/";
        strategy = "silent";
      };
      opdsCatalogs = [
        {
          id = "gutenberg";
          name = "Project Gutenberg";
          url = "https://m.gutenberg.org/ebooks.opds/";
        }
        {
          id = "standard";
          name = "Standard Ebooks";
          url = "https://standardebooks.org/feeds/opds";
        }
      ];
      globalReadSettings.customHighlightColors.red = "#ff0000";
      globalReadSettings.customThemes = [
        {
          name = "sepia";
          label = "Sepia";
          colors = {
            light = {
              bg = "#f4ecd8";
              fg = "#5b4636";
              primary = "#8b5e3c";
            };
            dark = {
              bg = "#2b2420";
              fg = "#e8dcc4";
              primary = "#c49a6c";
            };
          };
        }
      ];
    };
  };

  specialisation = {
    dropped.configuration.programs.readest.settings = lib.mkForce { telemetryEnabled = false; };
    emptied.configuration.programs.readest.settings = lib.mkForce { };
    disabled.configuration.programs.readest.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    readest=$HOME/.config/com.bilingify.readest/settings.json
    records=$XDG_STATE_HOME/home-manager/mutable-settings$HOME/.config/com.bilingify.readest
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
    # What Readest writes: on start it saves the file with top-level defaults
    # and the first level of the three settings groups filled in, plus a
    # device id for kosync; opening the catalog list adds a `contentId` and
    # `addedAt` to each catalog. The user renames a catalog and adds one.
    edit "$readest" '
      .libraryColumns = 6
      | .globalViewSettings.lineHeight = 1.6
      | .globalViewSettings.noteExportConfig.includeAuthor = true
      | .globalReadSettings.sideBarWidth = "15%"
      | .kosync += {deviceId: "c0ffee", checksumMethod: "binary"}
      | .opdsCatalogs |= map(. + {contentId: ("opds-" + .id), addedAt: 1767225600000})
      | .opdsCatalogs[1].name = "Standard"
      | .opdsCatalogs += [{id: "mine", name: "Mine", url: "https://example.org/opds"}]
    '

    # Fields of nested objects that Readest does not fill in with defaults
    # stay, rather than reading as undefined. Unchanged catalogs and themes go
    # whole, with what Readest added.
    activate ${generations.dropped}
    assertJson "$readest" '. == {
      telemetryEnabled: false,
      libraryColumns: 6,
      globalViewSettings: {lineHeight: 1.6, noteExportConfig: {includeTitle: false, includeAuthor: true}},
      globalReadSettings: {sideBarWidth: "15%", customHighlightColors: {red: "#ff0000"}},
      kosync: {
        enabled: true,
        serverUrl: "https://sync.example.org/",
        strategy: "silent",
        deviceId: "c0ffee",
        checksumMethod: "binary"
      },
      opdsCatalogs: [
        {
          id: "standard",
          name: "Standard",
          url: "https://standardebooks.org/feeds/opds",
          contentId: "opds-standard",
          addedAt: 1767225600000
        },
        {id: "mine", name: "Mine", url: "https://example.org/opds"}
      ]
    }'

    # Removing the last setting removes it too, and the record.
    activate ${generations.emptied}
    assertJson "$readest" '(has("telemetryEnabled") | not) and .kosync.strategy == "silent"'
    assertPathNotExists "$records/settings.json.json"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp "$readest" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff "$TMPDIR/before-disabled" "$readest" || fail "Disabling the module changed the file"
    activate ${generations.dropped}
    assertJson "$readest" '
      (has("libraryViewMode") or has("opdsCatalogs") or (.globalReadSettings | has("customThemes")) | not)
      and .kosync.strategy == "silent"
    '
  '';
}
