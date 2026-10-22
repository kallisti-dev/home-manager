{ stateVersion, removed }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  mkGeneration =
    name: settings:
    pkgs.writeShellScript name ''
      set -euo pipefail
      ${config.lib.bash.initHomeManagerLib}
      ${lib.hm.generators.mkImpureConfigMerger {
        inherit pkgs;
        format = "json";
        empty = "{}";
        jqOperation = "$dynamic * $static";
        path = "/@TMPDIR@/settings.json";
        staticSettings = builtins.toFile "${name}.json" (builtins.toJSON settings);
        removal.enable = config.home.mutableSettings.removeDropped;
      }}
    '';
  expected = {
    kept = true;
  }
  // lib.optionalAttrs (!removed) { dropped = true; };
in
{
  home.stateVersion = stateVersion;

  nmt.script = ''
    export XDG_STATE_HOME="$TMPDIR/state"
    for generation in \
      ${
        mkGeneration "first" {
          kept = true;
          dropped = true;
        }
      } \
      ${mkGeneration "second" { kept = true; }}; do
      substitute "$generation" "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
    done
    ${lib.getExe pkgs.jaq} -e '. == ${builtins.toJSON expected}' "$TMPDIR/settings.json" > /dev/null \
      || fail "Expected ${builtins.toJSON expected}, got $(cat "$TMPDIR/settings.json")"
  '';
}
