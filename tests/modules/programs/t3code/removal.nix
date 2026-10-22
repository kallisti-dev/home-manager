{
  config,
  lib,
  pkgs,
  ...
}:

let
  activations = [
    "t3codeSettingsActivation"
    "t3codeKeybindingsActivation"
    "t3codeClientSettingsActivation"
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
in
{
  home.homeDirectory = lib.mkForce "/@TMPDIR@/hm-user";
  home.mutableSettings.removeDropped = true;

  programs.t3code = {
    enable = true;
    package = config.lib.test.mkStubPackage { };
    userSettings = {
      defaultAutoPull = true;
      branchNamePrefix = "nix";
      providerInstances = {
        codex = {
          driver = "codex";
          config = {
            enabled = true;
            binaryPath = "codex";
          };
        };
        claude = {
          driver = "claudeAgent";
          config.binaryPath = "claude";
        };
      };
      textGenerationModelSelection = {
        provider = "codex";
        model = "gpt-5.5";
      };
      usageLimitSources.proxy = {
        kind = "cliproxy";
        url = "http://localhost:8317";
      };
      favorites = [
        {
          provider = "codex";
          model = "gpt-5.5";
        }
      ];
      deviceHosts = [
        {
          id = "mac";
          label = "Mac";
          target = "user@mac";
        }
      ];
    };
    keybindings = [
      {
        key = "mod+j";
        command = "terminal.toggle";
      }
      {
        key = "mod+d";
        command = "terminal.split";
        when = "terminalFocus";
      }
      {
        key = "mod+e";
        command = "editor.open";
      }
    ];
    clientSettings = {
      timestampFormat = "24-hour";
      snapShotShortcut = {
        kind = "modifier-pair";
        modifier = "alt";
      };
    };
  };

  specialisation = {
    dropped.configuration.programs.t3code = {
      userSettings = lib.mkForce { defaultAutoPull = true; };
      keybindings = lib.mkForce [
        {
          key = "mod+j";
          command = "terminal.toggle";
        }
      ];
      clientSettings = lib.mkForce { timestampFormat = "24-hour"; };
    };
    emptied.configuration.programs.t3code = {
      userSettings = lib.mkForce { };
      keybindings = lib.mkForce [ ];
      clientSettings = lib.mkForce { };
    };
    disabled.configuration.programs.t3code.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    t3=$HOME/.t3/userdata
    records=$XDG_STATE_HOME/home-manager/mutable-settings$t3
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
    # What T3 Code writes: every save folds `config.enabled` into the
    # instance, rewrites the legacy `provider` of a model selection and fills
    # in defaults; the effort picker adds `options`, and the settings panels
    # add favorites, hosts and keybindings and change declared values.
    edit "$t3/settings.json" '
      .providerInstances.codex |= (.enabled = .config.enabled | del(.config.enabled))
      | .providerInstances.claude.config.binaryPath = "/opt/claude"
      | .textGenerationModelSelection |= {
          instanceId: .provider,
          model: .model,
          options: [{id: "reasoningEffort", value: "high"}]
        }
      | .usageLimitSources.proxy += {managementKey: "", enabled: true}
      | .favorites += [{provider: "claudeAgent", model: "opus"}]
      | .deviceHosts = [
          ({kind: "ssh"} + .deviceHosts[0]),
          {kind: "ssh", id: "linux", label: "Linux", target: "user@linux"}
        ]
    '
    edit "$t3/keybindings.json" '
      [{key: "mod+k", command: "commandPalette.toggle"}]
      + map(if .key == "mod+e" then .command = "editor.close" else . end)
    '
    edit "$t3/client-settings.json" '
      .snapShotShortcut.modifier = "meta" | .chatWidth = "comfortable"
    '

    # Dropped entries go whole, with what T3 Code added, rather than leaving
    # fragments that make T3 Code ignore the file; changed entries stay whole.
    activate ${generations.dropped}
    assertJson "$t3/settings.json" '. == {
      defaultAutoPull: true,
      providerInstances: {claude: {driver: "claudeAgent", config: {binaryPath: "/opt/claude"}}},
      favorites: [{provider: "claudeAgent", model: "opus"}],
      deviceHosts: [{kind: "ssh", id: "linux", label: "Linux", target: "user@linux"}]
    }'
    assertJson "$t3/keybindings.json" '. == [
      {key: "mod+e", command: "editor.close"},
      {key: "mod+j", command: "terminal.toggle"},
      {key: "mod+k", command: "commandPalette.toggle"}
    ]'
    assertJson "$t3/client-settings.json" '. == {
      timestampFormat: "24-hour",
      snapShotShortcut: {kind: "modifier-pair", modifier: "meta"},
      chatWidth: "comfortable"
    }'

    # Removing the last declarations removes them too, and the records.
    activate ${generations.emptied}
    assertJson "$t3/settings.json" '. == {
      providerInstances: {claude: {driver: "claudeAgent", config: {binaryPath: "/opt/claude"}}},
      favorites: [{provider: "claudeAgent", model: "opus"}],
      deviceHosts: [{kind: "ssh", id: "linux", label: "Linux", target: "user@linux"}]
    }'
    assertJson "$t3/keybindings.json" '. == [
      {key: "mod+e", command: "editor.close"},
      {key: "mod+k", command: "commandPalette.toggle"}
    ]'
    assertJson "$t3/client-settings.json" '. == {
      snapShotShortcut: {kind: "modifier-pair", modifier: "meta"},
      chatWidth: "comfortable"
    }'
    for file in settings keybindings client-settings; do
      assertPathNotExists "$records/$file.json.json"
    done

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp -r "$t3" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff -r "$TMPDIR/before-disabled" "$t3" || fail "Disabling the module changed the files"
    activate ${generations.dropped}
    assertJson "$t3/settings.json" '. == {defaultAutoPull: true}'
  '';
}
