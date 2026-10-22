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
      ${configuration.home.activation.antigravitySettings.data or ""}
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

  programs.antigravity-cli = {
    enable = true;
    package = null;
    mutableSettings = true;
    settings = {
      colorScheme = "tokyo night";
      trustedWorkspaces = [ "/srv/declared" ];
    };
    permissions = {
      allow = [ "command(git)" ];
      ask = [ ];
      deny = [ "command(rm)" ];
    };
    mcpServers = {
      toggled = {
        command = "toggled-mcp";
        args = [ ];
      };
      edited = {
        command = "edited-mcp";
        args = [
          "--port"
          "1"
        ];
      };
      kept.serverUrl = "https://mcp.example.com/mcp";
    };
  };

  specialisation = {
    dropped.configuration.programs.antigravity-cli = {
      settings = lib.mkForce { colorScheme = "tokyo night"; };
      permissions = lib.mkForce { deny = [ "command(rm)" ]; };
      mcpServers = lib.mkForce { kept.serverUrl = "https://mcp.example.com/mcp"; };
    };
    emptied.configuration.programs.antigravity-cli = {
      settings = lib.mkForce { };
      permissions = lib.mkForce { };
      mcpServers = lib.mkForce { };
    };
    disabled.configuration.programs.antigravity-cli.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    settings=$HOME/.gemini/antigravity-cli/settings.json
    mcp=$HOME/.gemini/config/mcp_config.json
    records=$XDG_STATE_HOME/home-manager/mutable-settings$HOME/.gemini
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

    # Without records, empty settings create neither files nor records.
    activate ${generations.emptied}
    assertPathNotExists "$HOME/.gemini"
    assertPathNotExists "$XDG_STATE_HOME"

    activate ${generations.first}
    # What Antigravity CLI writes: permission prompts and workspace trust
    # append to the lists, including the one cleared by an empty list, and
    # `agy mcp disable` marks a server disabled and drops its empty `args`.
    # The user also edits a server's arguments.
    edit "$settings" '
      .permissions.allow += ["command(ls)"]
      | .permissions.ask += ["command(curl)"]
      | .trustedWorkspaces += ["/srv/mine"]
      | .altScreenMode = "always"
    '
    edit "$mcp" '
      .mcpServers.toggled = {command: "toggled-mcp", disabled: true}
      | .mcpServers.edited.args = ["--port", "2"]
    '

    # Permission rules and workspaces dropped from Nix go, those Antigravity
    # CLI added stay. A dropped server goes whole, with what Antigravity CLI
    # added, unless a declared value changed.
    activate ${generations.dropped}
    assertJson "$settings" '. == {
      colorScheme: "tokyo night",
      altScreenMode: "always",
      permissions: {allow: ["command(ls)"], ask: ["command(curl)"], deny: ["command(rm)"]},
      trustedWorkspaces: ["/srv/mine"]
    }'
    assertJson "$mcp" '. == {mcpServers: {
      edited: {command: "edited-mcp", args: ["--port", "2"]},
      kept: {serverUrl: "https://mcp.example.com/mcp"}
    }}'

    # Removing the last declarations removes them too, and the records.
    activate ${generations.emptied}
    assertJson "$settings" '. == {
      altScreenMode: "always",
      permissions: {allow: ["command(ls)"], ask: ["command(curl)"]},
      trustedWorkspaces: ["/srv/mine"]
    }'
    assertJson "$mcp" '. == {mcpServers: {edited: {command: "edited-mcp", args: ["--port", "2"]}}}'
    assertPathNotExists "$records/antigravity-cli/settings.json.json"
    assertPathNotExists "$records/config/mcp_config.json.json"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the records still describe the last merge.
    activate ${generations.first}
    cp -r "$HOME/.gemini" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff -r "$TMPDIR/before-disabled" "$HOME/.gemini" || fail "Disabling the module changed the files"
    activate ${generations.dropped}
    assertJson "$settings" '
      .permissions.deny == ["command(rm)"]
      and (.permissions | has("allow") | not)
      and (has("trustedWorkspaces") | not)
    '
    assertJson "$mcp" '.mcpServers | keys == ["kept"]'
  '';
}
