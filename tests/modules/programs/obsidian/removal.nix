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
      ${configuration.home.activation.obsidian.data or ""}
    '';
  generations = lib.mapAttrs mkActivation (
    {
      first = config;
    }
    // lib.mapAttrs (_: specialisation: specialisation.configuration) config.specialisation
  );
  vaultId = target: builtins.substring 0 16 (builtins.hashString "md5" target);
  notes = vaultId "notes";
  work = vaultId "Documents/work";
  configDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/obsidian"
    else
      ".config/obsidian";
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.obsidian = {
    enable = true;
    package = null;
    cli.enable = true;
    vaults = {
      notes = { };
      work.target = "Documents/work";
    };
  };

  specialisation = {
    dropped.configuration.programs.obsidian = {
      cli.enable = lib.mkForce false;
      vaults = lib.mkForce { notes = { }; };
    };
    emptied.configuration.programs.obsidian.vaults = lib.mkForce { };
    disabled.configuration.programs.obsidian.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    obsidian="$HOME/${configDir}/obsidian.json"
    activate() {
      substitute "$1" "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
    }
    # Vault paths come from the generated settings, which keep the declared
    # home directory rather than the test's.
    assertJson() {
      ${lib.getExe pkgs.jaq} --arg home ${lib.escapeShellArg config.home.homeDirectory} -e "$2" "$1" > /dev/null \
        || fail "Expected $2 in $1, got $(cat "$1")"
    }
    edit() {
      ${lib.getExe pkgs.jaq} "$2" "$1" > "$TMPDIR/edited"
      cat "$TMPDIR/edited" > "$1"
    }

    activate ${generations.first}
    assertJson "$obsidian" '.cli == true and .updateDisabled == true'
    # What Obsidian writes: when a vault was last opened and whether it is
    # open. Turning the CLI off in its settings deletes `cli`.
    edit "$obsidian" '
      .vaults["${notes}"] += {ts: 1767225600000, open: true}
      | .vaults["${work}"].ts = 1767225600001
      | del(.cli)
    '

    # A vault removed from the configuration stays listed as it is, since
    # Obsidian cannot start with an entry that lost its `path`, and deletes
    # the stored data of a vault it no longer lists.
    activate ${generations.dropped}
    assertJson "$obsidian" '. == {
      vaults: {
        "${notes}": {path: ($home + "/notes"), ts: 1767225600000, open: true},
        "${work}": {path: ($home + "/Documents/work"), ts: 1767225600001}
      },
      updateDisabled: true,
      cli: false
    }'

    # So does the last vault.
    activate ${generations.emptied}
    assertJson "$obsidian" '
      .vaults["${notes}"].path == $home + "/notes"
      and .vaults["${work}"].path == $home + "/Documents/work"
    '

    # Disabling the module changes nothing, and enabling it again applies the
    # declared settings.
    activate ${generations.first}
    assertJson "$obsidian" '.cli == true'
    cp "$obsidian" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff "$TMPDIR/before-disabled" "$obsidian" || fail "Disabling the module changed the file"
    activate ${generations.dropped}
    assertJson "$obsidian" '.cli == false and (.vaults | length) == 2'
  '';
}
