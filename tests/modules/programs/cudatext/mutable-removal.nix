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
      ${configuration.home.activation.cudatextSettings.data or ""}
    '';
  generations = lib.mapAttrs mkActivation (
    {
      first = config;
    }
    // lib.mapAttrs (_: specialisation: specialisation.configuration) config.specialisation
  );
  settingsDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/CudaText/settings"
    else
      ".config/cudatext/settings";
  pageUp = {
    name = "column select: page up";
    s1 = [ "Ctrl+PgUp" ];
  };
  lineEnd = {
    name = "caret to line end";
    s1 = [ "End" ];
  };
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.cudatext = {
    enable = true;
    package = null;
    mutableSettings = true;
    hotkeys = {
      "116" = pageUp;
      "153" = {
        name = "delete char right (delete)";
        s1 = [ "End" ];
      };
      "2823" = {
        name = "code tree: clear filter";
        s1 = [ "Home" ];
      };
    };
    userSettings = {
      numbers_style = 2;
      numbers_center = false;
    };
    lexerSettings.Python = {
      numbers_style = 1;
      tab_size = 4;
    };
    lexerHotkeys.Python = {
      "655464" = {
        name = "caret to line begin";
        s1 = [ "Home" ];
      };
      "655465" = lineEnd;
    };
  };

  specialisation = {
    dropped.configuration.programs.cudatext = {
      hotkeys = lib.mkForce { "116" = pageUp; };
      userSettings = lib.mkForce { numbers_style = 2; };
      lexerSettings = lib.mkForce { Python.numbers_style = 1; };
      lexerHotkeys = lib.mkForce { Python."655465" = lineEnd; };
    };
    emptied.configuration.programs.cudatext = {
      hotkeys = lib.mkForce { };
      userSettings = lib.mkForce { };
      lexerSettings = lib.mkForce { Python = { }; };
      lexerHotkeys = lib.mkForce { };
    };
    disabled.configuration.programs.cudatext.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    settings="$HOME/${settingsDir}"
    records="$XDG_STATE_HOME/home-manager/mutable-settings$settings"
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
    # What CudaText writes from its hotkey dialog: the command name, `s1`
    # and, once a second hotkey is added, `s2`. Choosing a theme writes a
    # user setting.
    edit "$settings/keys.json" '."153".s2 = ["Ctrl+D"] | ."2823".s1 = ["Ctrl+Home"]'
    edit "$settings/keys lexer Python.json" '."655464".s2 = ["Alt+Home"]'
    edit "$settings/user.json" '.ui_theme = "sub"'

    # A dropped hotkey goes whole rather than leaving `s2` alone, which would
    # unbind its default hotkey, and stays whole if its declared hotkey was
    # changed in CudaText.
    activate ${generations.dropped}
    assertJson "$settings/keys.json" '. == {
      "116": {name: "column select: page up", s1: ["Ctrl+PgUp"]},
      "2823": {name: "code tree: clear filter", s1: ["Ctrl+Home"]}
    }'
    assertJson "$settings/keys lexer Python.json" '. == {"655465": {name: "caret to line end", s1: ["End"]}}'
    assertJson "$settings/user.json" '. == {numbers_style: 2, ui_theme: "sub"}'
    assertJson "$settings/lexer Python.json" '. == {numbers_style: 1}'

    # Removing the last settings removes them too, and the records. A lexer
    # that is no longer declared keeps its file and record.
    activate ${generations.emptied}
    assertJson "$settings/keys.json" '. == {"2823": {name: "code tree: clear filter", s1: ["Ctrl+Home"]}}'
    assertJson "$settings/user.json" '. == {ui_theme: "sub"}'
    assertJson "$settings/lexer Python.json" '. == {}'
    assertJson "$settings/keys lexer Python.json" '. == {"655465": {name: "caret to line end", s1: ["End"]}}'
    for file in keys user "lexer Python"; do
      assertPathNotExists "$records/$file.json.json"
    done
    assertFileExists "$records/keys lexer Python.json.json"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the records still describe the last merge.
    activate ${generations.first}
    cp -r "$settings" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff -r "$TMPDIR/before-disabled" "$settings" || fail "Disabling the module changed the files"
    activate ${generations.dropped}
    assertJson "$settings/keys.json" 'keys == ["116"]'
    assertJson "$settings/user.json" '. == {numbers_style: 2, ui_theme: "sub"}'
  '';
}
