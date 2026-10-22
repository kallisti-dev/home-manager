{
  config,
  lib,
  pkgs,
  ...
}:

let
  activations = [
    "githubCopilotCliTrustedFolders"
    "githubCopilotCliSettings"
  ];
  mkActivation =
    name: configuration:
    pkgs.writeShellScript "activate-${name}" ''
      set -euo pipefail
      ${configuration.lib.bash.initHomeManagerLib}
      ${lib.concatMapStrings (
        entry: configuration.home.activation.${entry}.data or "" + "\n"
      ) activations}
    '';
  generations = lib.mapAttrs mkActivation (
    {
      first = config;
    }
    // lib.mapAttrs (_: specialisation: specialisation.configuration) config.specialisation
  );

  # Login and plugin state that Copilot CLI keeps in config.json.
  state = {
    firstLaunchAt = "2026-10-01T00:00:00.000Z";
    loggedInUsers = [
      {
        host = "https://github.com";
        login = "user";
      }
    ];
    lastLoggedInUser = {
      host = "https://github.com";
      login = "user";
    };
    installedPlugins = [
      {
        name = "plugin";
        marketplace = "team";
        enabled = true;
      }
    ];
  };
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.github-copilot-cli = {
    enable = true;
    package = null;
    mutableSettings = true;
    trustedFolders = [
      "/srv/declared"
      "/srv/dropped"
    ];
    settings = {
      model = "claude-sonnet-4.5";
      allowedUrls = [ "https://docs.example.com" ];
      disabledSkills = [ "declared-skill" ];
      permissions.allow = [ "shell(git:*)" ];
      sandbox.userPolicy.filesystem.readwritePaths = [ "/srv/declared" ];
      extraKnownMarketplaces.team.source = {
        source = "github";
        repo = "example/marketplace";
      };
    };
  };

  specialisation = {
    dropped.configuration.programs.github-copilot-cli = {
      trustedFolders = lib.mkForce [ "/srv/declared" ];
      settings = lib.mkForce { model = "claude-sonnet-4.5"; };
    };
    emptied.configuration.programs.github-copilot-cli = {
      trustedFolders = lib.mkForce [ ];
      settings = lib.mkForce { };
    };
    disabled.configuration.programs.github-copilot-cli.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    copilot=$HOME/.copilot
    records=$XDG_STATE_HOME/home-manager/mutable-settings$copilot
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
    # Every merge leaves Copilot CLI's own state in config.json alone.
    assertState() {
      assertJson "$copilot/config.json" \
        ${lib.escapeShellArg "del(.trustedFolders) == ${builtins.toJSON state}"}" and $1"
    }

    # Copilot CLI's config.json, starting with its comment header. Without
    # declarations or a record, the merges neither rewrite it nor create
    # settings.json or records.
    mkdir -p "$copilot"
    cat > "$copilot/config.json" <<'JSON'
    // This file is managed by Copilot CLI.
    ${builtins.toJSON (state // { trustedFolders = [ "/srv/mine" ]; })}
    JSON
    cp "$copilot/config.json" "$TMPDIR/initial-config.json"
    activate ${generations.emptied}
    cmp "$TMPDIR/initial-config.json" "$copilot/config.json" || fail "config.json was rewritten"
    assertPathNotExists "$copilot/settings.json"
    assertPathNotExists "$XDG_STATE_HOME"

    activate ${generations.first}
    assertState '.trustedFolders == ["/srv/mine", "/srv/declared", "/srv/dropped"]'
    # What Copilot CLI writes: `copilot config <list> <entry>`, /skills and
    # the /sandbox dialog add entries to the lists, and /theme sets a value.
    # The user also enables auto-update for the marketplace.
    edit "$copilot/settings.json" '
      .permissions.allow += ["shell(ls)"]
      | .disabledSkills += ["mine"]
      | .sandbox.userPolicy.filesystem.readwritePaths += ["/srv/mine"]
      | .extraKnownMarketplaces.team.autoUpdate = true
      | .theme = "dim"
    '

    # Entries dropped from Nix go, those Copilot CLI added stay, and the
    # dropped marketplace goes whole. The dropped folder is untrusted even if
    # Copilot CLI was also asked to trust it, as it keeps one entry per folder.
    activate ${generations.dropped}
    assertJson "$copilot/settings.json" '. == {
      model: "claude-sonnet-4.5",
      theme: "dim",
      disabledSkills: ["mine"],
      permissions: {allow: ["shell(ls)"]},
      sandbox: {userPolicy: {filesystem: {readwritePaths: ["/srv/mine"]}}}
    }'
    assertState '.trustedFolders == ["/srv/mine", "/srv/declared"]'

    # Removing the last declarations removes them too, and the records.
    activate ${generations.emptied}
    assertJson "$copilot/settings.json" '. == {
      theme: "dim",
      disabledSkills: ["mine"],
      permissions: {allow: ["shell(ls)"]},
      sandbox: {userPolicy: {filesystem: {readwritePaths: ["/srv/mine"]}}}
    }'
    assertState '.trustedFolders == ["/srv/mine"]'
    assertPathNotExists "$records/settings.json.json"
    assertPathNotExists "$records/config.json.json"

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the records still describe the last merge.
    activate ${generations.first}
    cp -r "$copilot" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff -r "$TMPDIR/before-disabled" "$copilot" || fail "Disabling the module changed the files"
    activate ${generations.dropped}
    assertJson "$copilot/settings.json" '. == {model: "claude-sonnet-4.5", theme: "dim"}'
    assertState '.trustedFolders == ["/srv/mine", "/srv/declared"]'
  '';
}
