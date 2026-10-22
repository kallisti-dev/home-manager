{
  config,
  lib,
  pkgs,
  ...
}:

let
  profiles = [
    "writable"
    "empty"
  ];
  mkActivation =
    name: configuration:
    pkgs.writeShellScript "activate-${name}" ''
      set -euo pipefail
      ${configuration.lib.bash.initHomeManagerLib}
      ${lib.concatMapStrings (
        profile: configuration.home.activation."colima-${profile}MutableSettings".data or "" + "\n"
      ) profiles}
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

  services.colima = {
    enable = true;
    profiles = {
      writable = {
        mutableSettings = true;
        settings = {
          runtime = "containerd";
          cpu = 4;
          env.TOKEN = "test-only";
          mounts = [ { location = "~/src"; } ];
        };
      };
      empty.mutableSettings = true;
    };
  };

  specialisation = {
    dropped.configuration.services.colima.profiles.writable.settings = lib.mkForce { cpu = 4; };
    emptied.configuration.services.colima.profiles.writable.settings = lib.mkForce { };
    immutable.configuration.services.colima.profiles.writable.mutableSettings = lib.mkForce false;
    disabled.configuration.services.colima.enable = lib.mkForce false;
  };

  nmt.script =
    let
      cleanup =
        config.specialisation.immutable.configuration.home.activation.colimaImmutableSettings.data;
    in
    # Switching the profile back to immutable settings cleans up its file.
    assert lib.hasInfix "mutable-settings" cleanup && lib.hasInfix "writable/colima.yaml" cleanup;
    ''
      export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
      colima=$HOME/.colima
      records=$XDG_STATE_HOME/home-manager/mutable-settings$colima
      activate() {
        substitute "$1" "$TMPDIR/activate" --subst-var TMPDIR
        chmod +x "$TMPDIR/activate"
        "$TMPDIR/activate"
      }
      assertYaml() {
        ${lib.getExe pkgs.jaq} --from yaml -e "$2" "$1" > /dev/null \
          || fail "Expected $2 in $1, got $(cat "$1")"
      }
      edit() {
        ${lib.getExe pkgs.jaq} --from yaml --to yaml "$2" "$1" > "$TMPDIR/edited"
        cat "$TMPDIR/edited" > "$1"
      }

      # A mutable profile without settings neither creates a file nor a record.
      activate ${generations.first}
      assertPathNotExists "$colima/empty"
      assertPathNotExists "$records/empty"

      # What `colima start` saves: every setting, and `writable` in each mount.
      edit "$colima/writable/colima.yaml" '.memory = 2 | .disk = 100 | .mounts[0].writable = false'

      # `runtime` stays, or Colima would ignore the rest of the file. The
      # mounts Colima changed stay as a whole.
      activate ${generations.dropped}
      assertYaml "$colima/writable/colima.yaml" '. == {
        runtime: "containerd",
        cpu: 4,
        mounts: [{location: "~/src", writable: false}],
        memory: 2,
        disk: 100
      }'

      # Removing the last setting removes it too, and the record.
      activate ${generations.emptied}
      assertYaml "$colima/writable/colima.yaml" '. == {
        runtime: "containerd",
        mounts: [{location: "~/src", writable: false}],
        memory: 2,
        disk: 100
      }'
      assertPathNotExists "$records/writable/colima.yaml.json"
      assertPathNotExists "$colima/empty"

      # Disabling the module changes nothing. Enabling it again removes what
      # was dropped meanwhile, as the record still describes the last merge.
      activate ${generations.first}
      cp -r "$colima" "$TMPDIR/before-disabled"
      activate ${generations.disabled}
      diff -r "$TMPDIR/before-disabled" "$colima" || fail "Disabling the module changed the files"
      activate ${generations.dropped}
      assertYaml "$colima/writable/colima.yaml" '. == {runtime: "containerd", cpu: 4, memory: 2, disk: 100}'
    '';
}
