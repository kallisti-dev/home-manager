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
      ${configuration.home.activation.claudeCodeSettings.data or ""}
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

  programs.claude-code = {
    enable = true;
    package = null;
    mutableSettings = true;
    settings = {
      theme = "dark";
      statusLine = {
        type = "command";
        command = "status";
      };
      fileSuggestion = {
        type = "command";
        command = "suggest";
      };
      permissions = {
        allow = [
          "Read"
          "Bash(git status)"
        ];
        defaultMode = "plan";
      };
      autoMode = {
        allow = [
          "$defaults"
          "Running nix build is fine"
        ];
        soft_deny = [
          "$defaults"
          "Never run terraform apply"
        ];
      };
      hooks.SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = "/nix/store/hook";
            }
          ];
        }
      ];
    };
    marketplaces = {
      kept = ./test-marketplace;
      dropped = ./test-marketplace;
      repointed = ./test-marketplace;
    };
  };

  specialisation = {
    dropped.configuration.programs.claude-code = {
      settings = lib.mkForce {
        theme = "dark";
        permissions.defaultMode = "plan";
      };
      marketplaces = lib.mkForce { kept = ./test-marketplace; };
    };
    emptied.configuration.programs.claude-code = {
      settings = lib.mkForce { };
      marketplaces = lib.mkForce { };
    };
    immutable.configuration.programs.claude-code.mutableSettings = lib.mkForce false;
  };

  nmt.script =
    let
      cleanup =
        config.specialisation.immutable.configuration.home.activation.claudeCodeImmutableSettings.data;
    in
    # Switching back to immutable settings cleans up both merged files.
    assert lib.hasInfix "mutable-settings" cleanup && lib.hasInfix "known_marketplaces.json" cleanup;
    ''
      export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
      claude=$HOME/.claude
      records=$XDG_STATE_HOME/home-manager/mutable-settings$claude
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
      # What Claude Code writes: /statusline rewrites the command, /permissions
      # adds a rule, the auto-mode setup adds a rule after `$defaults`, the
      # auto-update toggle annotates the marketplace, and
      # `claude plugin marketplace add` re-points one.
      edit "$claude/settings.json" '
        .statusLine.command = "user-status"
        | .permissions.allow += ["Edit"]
        | .autoMode.soft_deny += ["Never delete Route53 zones"]
        | .extraKnownMarketplaces.dropped.autoUpdate = true
      '
      edit "$claude/plugins/known_marketplaces.json" '
        .dropped.lastUpdated = "2026-10-01T00:00:00Z"
        | .repointed.source.path = "/elsewhere"
        | .repointed.installLocation = "/elsewhere"
      '

      activate ${generations.dropped}
      assertJson "$claude/settings.json" '
        .theme == "dark"
        and .permissions == {allow: ["Edit"], defaultMode: "plan"}
        and .statusLine == {type: "command", command: "user-status"}
        and (has("fileSuggestion") or has("hooks") | not)
        and .autoMode == {soft_deny: ["$defaults", "Never delete Route53 zones"]}
        and (.extraKnownMarketplaces | keys) == ["kept"]
      '
      assertJson "$claude/plugins/known_marketplaces.json" '
        (keys == ["kept", "repointed"]) and .repointed.installLocation == "/elsewhere"
      '

      # Removing the last declarations leaves only what Claude Code changed or
      # added, and drops the records.
      activate ${generations.emptied}
      assertJson "$claude/settings.json" '. == {
        permissions: {allow: ["Edit"]},
        autoMode: {soft_deny: ["$defaults", "Never delete Route53 zones"]},
        statusLine: {type: "command", command: "user-status"}
      }'
      assertJson "$claude/plugins/known_marketplaces.json" 'keys == ["repointed"]'
      assertPathNotExists "$records/settings.json.json"
      assertPathNotExists "$records/plugins/known_marketplaces.json.json"
    '';
}
