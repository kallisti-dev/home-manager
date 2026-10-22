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
      ${configuration.home.activation.andcliMutableSettings.data or ""}
      ${configuration.home.activation.andcliImmutableSettings.data or ""}
    '';
  generations = lib.mapAttrs mkActivation (
    {
      first = config;
    }
    // lib.mapAttrs (_: specialisation: specialisation.configuration) config.specialisation
  );
  configDir = if pkgs.stdenv.hostPlatform.isDarwin then "Library/Application Support" else ".config";
  linkedFile =
    lib.findFirst (file: lib.hasSuffix "andcli/config.yaml" file.target)
      (throw "andcli's config.yaml is not linked")
      (lib.attrValues config.specialisation.immutable.configuration.home.file);
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.andcli = {
    enable = true;
    package = null;
    mutableSettings = true;
    settings = {
      file = "/vaults/aegis.json";
      type = "aegis";
      clipboard_cmd = "wl-copy";
      session_timeout = 600;
      options.show_tokens = true;
      theme.base = "#ffffff";
    };
  };

  specialisation = {
    dropped.configuration.programs.andcli.settings = lib.mkForce {
      file = "/vaults/aegis.json";
      type = "aegis";
    };
    emptied.configuration.programs.andcli.settings = lib.mkForce { };
    disabled.configuration.programs.andcli.enable = lib.mkForce false;
    immutable.configuration.programs.andcli.mutableSettings = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    settings="$HOME/${configDir}/andcli/config.yaml"
    record="$XDG_STATE_HOME/home-manager/mutable-settings$settings.json"
    activate() {
      substitute "$1" "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
    }
    assertYaml() {
      ${lib.getExe pkgs.jaq} --from yaml -e "$2" "$1" > /dev/null || fail "Expected $2 in $1, got $(cat "$1")"
    }
    edit() {
      ${lib.getExe pkgs.jaq} --from yaml --to yaml "$2" "$1" > "$TMPDIR/edited"
      cat "$TMPDIR/edited" > "$1"
    }

    # Without a record, empty settings create nothing.
    activate ${generations.emptied}
    assertPathNotExists "$settings"
    assertPathNotExists "$record"

    # What andcli writes when a command-line flag changes a setting: every
    # key it knows, with the clipboard command resolved to its path.
    activate ${generations.first}
    edit "$settings" '
      .clipboard_cmd = "/run/current-system/sw/bin/wl-copy"
      | .options.show_usernames = false
      | .theme.green = "#00ff00"
    '

    # Dropped settings go unless andcli changed them. The options and the
    # theme go whole, with what andcli wrote into them, so that andcli falls
    # back to its defaults instead of reading the missing options as false.
    activate ${generations.dropped}
    assertYaml "$settings" '. == {
      file: "/vaults/aegis.json",
      type: "aegis",
      clipboard_cmd: "/run/current-system/sw/bin/wl-copy"
    }'

    # Removing the last declarations removes them too, and the record.
    activate ${generations.emptied}
    assertYaml "$settings" '. == {clipboard_cmd: "/run/current-system/sw/bin/wl-copy"}'
    assertPathNotExists "$record"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp "$settings" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    assertFileContent "$settings" "$TMPDIR/before-disabled"
    activate ${generations.dropped}
    assertYaml "$settings" '(has("session_timeout") or has("options") | not)'

    # Switching back to immutable settings drops the record and leaves the
    # file to the usual collision handling.
    export newGenPath=$TMPDIR/generation
    linked="$newGenPath/home-files/${linkedFile.target}"
    mkdir -p "$(dirname "$linked")"
    cp ${linkedFile.source} "$linked"
    activate ${generations.immutable}
    assertFileExists "$settings"
    assertPathNotExists "$record"
  '';
}
