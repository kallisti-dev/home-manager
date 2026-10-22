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
      ${configuration.home.activation.codexMutableSettings.data or ""}
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

  programs.mcp = {
    enable = true;
    servers.shared.command = "shared-mcp";
  };

  programs.codex = {
    enable = true;
    package = null;
    mutableSettings = true;
    enableMcpIntegration = true;
    marketplaces.team = ./sample-marketplace;
    settings = {
      model = "gpt-5";
      projects."/srv/project".trust_level = "trusted";
      mcp_servers = {
        approved = {
          command = "approved-mcp";
          args = [ ];
          enabled = true;
        };
        edited = {
          command = "edited-mcp";
          args = [
            "--port"
            "1"
          ];
        };
        switched.command = "switched-mcp";
      };
      tool_suggest.disabled_tools = [
        {
          type = "plugin";
          id = "declared";
        }
      ];
      skills.config = [
        {
          name = "declared";
          enabled = false;
        }
      ];
    };
  };

  specialisation = {
    dropped.configuration = {
      programs.mcp.servers = lib.mkForce { };
      programs.codex = {
        marketplaces = lib.mkForce { };
        settings = lib.mkForce {
          model = "gpt-5";
          mcp_servers.switched.url = "https://mcp.example.com/mcp";
        };
      };
    };
    emptied.configuration = {
      programs.mcp.servers = lib.mkForce { };
      programs.codex = {
        marketplaces = lib.mkForce { };
        settings = lib.mkForce { };
      };
    };
    disabled.configuration.programs.codex.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    settings=$HOME/.codex/config.toml
    record=$XDG_STATE_HOME/home-manager/mutable-settings$settings.json
    activate() {
      substitute "$1" "$TMPDIR/activate" --subst-var TMPDIR
      chmod +x "$TMPDIR/activate"
      "$TMPDIR/activate"
    }
    assertToml() {
      ${lib.getExe pkgs.jaq} --from toml -e "$2" "$1" > /dev/null \
        || fail "Expected $2 in $1, got $(cat "$1")"
    }
    edit() {
      ${lib.getExe pkgs.jaq} --from toml --to toml "$2" "$1" > "$TMPDIR/edited"
      cat "$TMPDIR/edited" > "$1"
    }

    # Without a record, empty settings create neither a file nor a record.
    activate ${generations.emptied}
    assertPathNotExists "$settings"
    assertPathNotExists "$record"

    activate ${generations.first}
    assertToml "$settings" '.features.plugins and (.mcp_servers | keys) == ["approved", "edited", "shared", "switched"]'
    # What Codex writes: "Always allow" on a tool records its approval in the
    # server, `codex mcp add` rewrites servers without `enabled = true` and
    # empty `args`, and disabling a tool suggestion or a skill appends to
    # those lists. The user also edits a server's arguments.
    edit "$settings" '
      .mcp_servers.approved = {
        command: "approved-mcp",
        tools: {search: {approval_mode: "approve"}}
      }
      | .mcp_servers.edited.args = ["--port", "2"]
      | .tool_suggest.disabled_tools += [{type: "connector", id: "mine"}]
      | .skills.config += [{path: "/srv/skills/mine/SKILL.md", enabled: false}]
      | .model_reasoning_effort = "high"
    '

    # A dropped server goes whole, with the approval Codex added, rather than
    # leaving an entry Codex cannot load, unless a declared value changed.
    # A server that switches to `url` loses its `command`.
    activate ${generations.dropped}
    assertToml "$settings" '. == {
      model: "gpt-5",
      model_reasoning_effort: "high",
      mcp_servers: {
        edited: {command: "edited-mcp", args: ["--port", "2"]},
        switched: {url: "https://mcp.example.com/mcp"}
      },
      tool_suggest: {disabled_tools: [{type: "connector", id: "mine"}]},
      skills: {config: [{path: "/srv/skills/mine/SKILL.md", enabled: false}]}
    }'

    # Removing the last declarations removes them too, and the record.
    activate ${generations.emptied}
    assertToml "$settings" '. == {
      model_reasoning_effort: "high",
      mcp_servers: {edited: {command: "edited-mcp", args: ["--port", "2"]}},
      tool_suggest: {disabled_tools: [{type: "connector", id: "mine"}]},
      skills: {config: [{path: "/srv/skills/mine/SKILL.md", enabled: false}]}
    }'
    assertPathNotExists "$record"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp "$settings" "$TMPDIR/before-disabled"
    cp "$record" "$TMPDIR/record-before-disabled"
    activate ${generations.disabled}
    cmp "$TMPDIR/before-disabled" "$settings" || fail "Disabling the module changed the file"
    cmp "$TMPDIR/record-before-disabled" "$record" || fail "Disabling the module changed the record"
    activate ${generations.dropped}
    assertToml "$settings" '
      (.mcp_servers | keys) == ["switched"]
      and (has("features") or has("marketplaces") or has("projects") or has("tool_suggest") or has("skills") | not)
    '
  '';
}
