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
      ${configuration.home.activation.herdrMutableSettings.data or ""}
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

  programs.herdr = {
    enable = true;
    package = pkgs.writeShellScriptBin "herdr" ''
      echo "$*" >> "$HERDR_LOG"
    '';
    mutableSettings = true;
    settings = {
      onboarding = false;
      theme.name = "catppuccin";
      ui.sound.enabled = true;
      keys = {
        next_tab = [ "prefix+n" ];
        command = [
          {
            key = "prefix+l";
            type = "plugin_action";
            command = "example.layout.apply";
          }
        ];
      };
    };
  };

  specialisation = {
    dropped.configuration.programs.herdr.settings = lib.mkForce {
      onboarding = false;
      keys.next_tab = [ "prefix+n" ];
    };
    emptied.configuration.programs.herdr.settings = lib.mkForce { };
    disabled.configuration.programs.herdr.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    export HERDR_LOG=$TMPDIR/herdr.log
    : > "$HERDR_LOG"
    settings=$HOME/.config/herdr/config.toml
    record=$XDG_STATE_HOME/home-manager/mutable-settings$settings.json
    activate() {
      substitute "$1" "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
    }
    assertToml() {
      ${lib.getExe pkgs.jaq} --from toml -e "$2" "$1" > /dev/null || fail "Expected $2 in $1, got $(cat "$1")"
    }
    assertReloads() {
      [[ "$(grep -cx 'server reload-config' "$HERDR_LOG")" == "$1" ]] \
        || fail "Expected $1 reloads of Herdr, got: $(cat "$HERDR_LOG")"
    }
    edit() {
      ${lib.getExe pkgs.jaq} --from toml --to toml "$2" "$1" > "$TMPDIR/edited"
      cat "$TMPDIR/edited" > "$1"
    }

    # Without a record, empty settings neither create the file nor reload
    # Herdr.
    activate ${generations.emptied}
    assertPathNotExists "$settings"
    assertPathNotExists "$record"
    assertReloads 0

    # Herdr is reloaded only when the merge changes the file.
    activate ${generations.first}
    assertReloads 1
    activate ${generations.first}
    assertReloads 1

    # What Herdr writes: picking a theme turns off automatic switching, and
    # its settings change scalars in place.
    edit "$settings" '
      .theme.name = "dracula"
      | .theme.auto_switch = false
      | .ui.toast = {delivery: "terminal"}
    '

    # Dropped settings go unless Herdr changed them, and what Herdr added
    # stays.
    activate ${generations.dropped}
    assertToml "$settings" '. == {
      onboarding: false,
      keys: {next_tab: ["prefix+n"]},
      theme: {name: "dracula", auto_switch: false},
      ui: {toast: {delivery: "terminal"}}
    }'
    assertReloads 2

    # Removing the last declarations removes them too, and the record, and
    # reloads Herdr once.
    activate ${generations.emptied}
    assertToml "$settings" '. == {
      theme: {name: "dracula", auto_switch: false},
      ui: {toast: {delivery: "terminal"}}
    }'
    assertPathNotExists "$record"
    assertReloads 3
    activate ${generations.emptied}
    assertReloads 3

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp "$settings" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    assertFileContent "$settings" "$TMPDIR/before-disabled"
    activate ${generations.dropped}
    assertToml "$settings" '(.ui | has("sound") | not) and (.keys | has("command") | not)'
  '';
}
