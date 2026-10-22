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
      ${configuration.home.activation.vesktopSettings.data or ""}
    '';
  generations = lib.mapAttrs mkActivation (
    {
      first = config;
    }
    // lib.mapAttrs (_: specialisation: specialisation.configuration) config.specialisation
  );
  configDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/vesktop"
    else
      ".config/vesktop";
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.vesktop = {
    enable = true;
    package = null;
    mutableSettings = true;
    settings = {
      tray = false;
      spellCheckLanguages = [ "en-US" ];
    };
    vencord = {
      mutableSettings = true;
      settings = {
        useQuickCss = true;
        plugins = {
          CrashHandler.enabled = false;
          FakeNitro.enabled = true;
          MessageLogger = {
            enabled = true;
            ignoreSelf = true;
            ignoreBots = true;
          };
          TextReplace.enabled = true;
        };
        enabledThemes = [ "nix.css" ];
        themeLinks = [ "https://example.com/nix.css" ];
      };
    };
  };

  specialisation = {
    dropped.configuration.programs.vesktop = {
      settings = lib.mkForce { tray = false; };
      vencord.settings = lib.mkForce {
        useQuickCss = true;
        plugins.FakeNitro.enabled = true;
      };
    };
    emptied.configuration.programs.vesktop = {
      settings = lib.mkForce { };
      vencord.settings = lib.mkForce { };
    };
    disabled.configuration.programs.vesktop.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    vesktop="$HOME/${configDir}"
    records="$XDG_STATE_HOME/home-manager/mutable-settings$vesktop"
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
    # What the applications write: Vesktop rewrites the spellcheck languages
    # when one is toggled, Vencord writes the defaults of plugin settings into
    # existing plugin entries, and its settings change plugins and themes.
    edit "$vesktop/settings.json" '.spellCheckLanguages += ["de"] | .arRPC = true'
    edit "$vesktop/settings/settings.json" '
      .plugins.CrashHandler.attemptToPreventCrashes = true
      | .plugins.MessageLogger.ignoreSelf = false
      | .plugins.TextReplace.stringRules = [{find: "brb", replace: "be right back"}]
      | .enabledThemes += ["mine.css"]
      | .notifications = {timeout: 5000}
    '

    # A dropped plugin keeps `enabled`, so it is not turned off, and the data
    # stored in its entry, while its other declared settings go unless they
    # were changed in Vencord. Languages and themes added in the applications
    # stay.
    activate ${generations.dropped}
    assertJson "$vesktop/settings.json" '. == {tray: false, spellCheckLanguages: ["de"], arRPC: true}'
    assertJson "$vesktop/settings/settings.json" '. == {
      useQuickCss: true,
      plugins: {
        CrashHandler: {enabled: false, attemptToPreventCrashes: true},
        FakeNitro: {enabled: true},
        MessageLogger: {enabled: true, ignoreSelf: false},
        TextReplace: {enabled: true, stringRules: [{find: "brb", replace: "be right back"}]}
      },
      enabledThemes: ["mine.css"],
      notifications: {timeout: 5000}
    }'

    # Removing the last settings removes them too, and the records.
    activate ${generations.emptied}
    assertJson "$vesktop/settings.json" '. == {spellCheckLanguages: ["de"], arRPC: true}'
    assertJson "$vesktop/settings/settings.json" '. == {
      plugins: {
        CrashHandler: {enabled: false, attemptToPreventCrashes: true},
        FakeNitro: {enabled: true},
        MessageLogger: {enabled: true, ignoreSelf: false},
        TextReplace: {enabled: true, stringRules: [{find: "brb", replace: "be right back"}]}
      },
      enabledThemes: ["mine.css"],
      notifications: {timeout: 5000}
    }'
    assertPathNotExists "$records/settings.json.json"
    assertPathNotExists "$records/settings/settings.json.json"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the records still describe the last merge.
    activate ${generations.first}
    cp -r "$vesktop" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff -r "$TMPDIR/before-disabled" "$vesktop" || fail "Disabling the module changed the files"
    activate ${generations.dropped}
    assertJson "$vesktop/settings/settings.json" '
      .useQuickCss == true
      and (has("enabledThemes") | not)
      and .plugins.MessageLogger == {enabled: true}
      and .plugins.TextReplace.stringRules == [{find: "brb", replace: "be right back"}]
    '
  '';
}
