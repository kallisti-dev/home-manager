{
  config,
  lib,
  pkgs,
  ...
}:

let
  activations = [
    "zedSettingsActivation"
    "zedKeymapActivation"
    "zedTasksActivation"
    "zedDebugActivation"
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

  programs.zed-editor = {
    enable = true;
    package = config.lib.test.mkStubPackage { };
    userSettings = {
      vim_mode = true;
      theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };
      icon_theme = {
        mode = "system";
        light = "Zed (Default)";
        dark = "Zed (Default)";
      };
      agent = {
        default_model = {
          provider = "anthropic";
          model = "claude-sonnet";
        };
        profiles.review = {
          name = "Review";
          tools.read_file = true;
        };
        favorite_models = [
          {
            provider = "anthropic";
            model = "claude-haiku";
          }
        ];
        sandbox_permissions.network_hosts = [ "github.com" ];
      };
      agent_servers.my-agent = {
        type = "custom";
        command = "my-agent";
        args = [ ];
      };
      terminal.shell.with_arguments = {
        program = "zsh";
        args = [ "-l" ];
      };
      context_servers.notes = {
        command = "notes-mcp";
        args = [ ];
      };
      ssh_connections = [ { host = "build"; } ];
    };
    userKeymaps = [
      {
        context = "Editor";
        bindings = {
          ctrl-a = "editor::SelectAll";
          ctrl-b = "editor::Backspace";
        };
      }
    ];
    userTasks = [
      {
        label = "build";
        command = "make";
      }
      {
        label = "test";
        command = "make test";
      }
    ];
  };

  specialisation = {
    dropped.configuration.programs.zed-editor = {
      userSettings = lib.mkForce { vim_mode = true; };
      userKeymaps = lib.mkForce [
        {
          context = "Editor";
          bindings.ctrl-a = "editor::SelectAll";
        }
      ];
      userTasks = lib.mkForce [
        {
          label = "test";
          command = "make test";
        }
      ];
    };
    emptied.configuration.programs.zed-editor = {
      userSettings = lib.mkForce { };
      userKeymaps = lib.mkForce [ ];
      userTasks = lib.mkForce [ ];
    };
    disabled.configuration.programs.zed-editor.enable = lib.mkForce false;
  };

  nmt.script = ''
    export HOME=$TMPDIR/hm-user XDG_STATE_HOME=$TMPDIR/hm-user/.local/state
    zed=$HOME/.config/zed
    records=$XDG_STATE_HOME/home-manager/mutable-settings$zed
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

    # The empty debug configuration neither creates a file nor a record.
    activate ${generations.first}
    assertPathNotExists "$zed/debug.json"
    assertPathNotExists "$records/debug.json.json"

    # What Zed writes into the declared entries. The next activation merges
    # the new keymap section into the declared one, and replaces the declared
    # lists, so Zed adds to those afterwards.
    edit "$zed/keymap.json" '. + [{context: "Editor", bindings: {"ctrl-u": "editor::Undo"}}]'
    edit "$zed/tasks.json" '. + [{label: "mine", command: "true"}]'
    activate ${generations.first}
    edit "$zed/settings.json" '
      .agent.profiles.review.tools.terminal = true
      | .agent.default_profile = "review"
      | .agent.default_model.enable_thinking = true
      | .agent.favorite_models += [{provider: "openai", model: "gpt"}]
      | .agent.sandbox_permissions.network_hosts += ["crates.io"]
      | .agent_servers["my-agent"].default_mode = "plan"
      | .context_servers.notes.enabled = false
      | .ssh_connections += [{host: "laptop"}]
      | .theme.dark = "Ayu Dark"
      | .terminal.shell.with_arguments.title_override = "dev"
      | .buffer_font_size = 15
    '

    # Dropped entries go whole, with what Zed added, rather than leaving
    # fragments Zed cannot read, unless Zed changed a declared value, as in
    # the theme. The default profile Zed recorded goes with its profile.
    activate ${generations.dropped}
    assertJson "$zed/settings.json" '. == {
      vim_mode: true,
      theme: {mode: "system", light: "One Light", dark: "Ayu Dark"},
      agent: {
        favorite_models: [{provider: "openai", model: "gpt"}],
        sandbox_permissions: {network_hosts: ["crates.io"]}
      },
      ssh_connections: [{host: "laptop"}],
      buffer_font_size: 15
    }'
    assertJson "$zed/keymap.json" '. == [{context: "Editor", bindings: {"ctrl-a": "editor::SelectAll", "ctrl-u": "editor::Undo"}}]'
    assertJson "$zed/tasks.json" '. == [{label: "mine", command: "true"}, {label: "test", command: "make test"}]'

    # Removing the last declarations removes them too, and the records.
    activate ${generations.emptied}
    assertJson "$zed/settings.json" '. == {
      theme: {mode: "system", light: "One Light", dark: "Ayu Dark"},
      agent: {
        favorite_models: [{provider: "openai", model: "gpt"}],
        sandbox_permissions: {network_hosts: ["crates.io"]}
      },
      ssh_connections: [{host: "laptop"}],
      buffer_font_size: 15
    }'
    assertJson "$zed/keymap.json" '. == [{context: "Editor", bindings: {"ctrl-u": "editor::Undo"}}]'
    assertJson "$zed/tasks.json" '. == [{label: "mine", command: "true"}]'
    for file in settings keymap tasks; do
      assertPathNotExists "$records/$file.json.json"
    done

    # Disabling the module changes nothing. Enabling it again removes what
    # was dropped meanwhile, as the record still describes the last merge.
    activate ${generations.first}
    cp -r "$zed" "$TMPDIR/before-disabled"
    activate ${generations.disabled}
    diff -r "$TMPDIR/before-disabled" "$zed" || fail "Disabling the module changed the files"
    activate ${generations.dropped}
    assertJson "$zed/settings.json" '
      .vim_mode == true
      and (.agent | has("profiles") | not)
      and (has("icon_theme") or has("agent_servers") or has("terminal") or has("context_servers") | not)
    '
  '';
}
