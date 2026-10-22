{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    literalExpression
    mkIf
    mkMerge
    mkOption
    types
    ;

  cfg = config.programs.zed-editor;
  jsonFormat = pkgs.formats.json { };
  json5 = pkgs.python3Packages.toPythonApplication pkgs.python3Packages.json5;

  transformedMcpServers = lib.optionalAttrs (cfg.enableMcpIntegration && config.programs.mcp.enable) (
    lib.mapAttrs (
      name: server:
      # See:
      #
      # - https://zed.dev/docs/ai/mcp
      # - https://github.com/zed-industries/zed/discussions/53780
      # - https://github.com/zed-industries/zed/blob/v1.6.3/crates/project/src/project_settings.rs#L182
      (lib.optionalAttrs (server.command != null) { args = [ ]; })
      // (lib.hm.mcp.transformMcpServer {
        inherit server;
        extraTransforms = [
          (lib.hm.mcp.wrapEnvFilesCommand { inherit pkgs name; })
        ];
      })
    ) config.programs.mcp.servers
  );

  settingMcpServers = lib.attrByPath [ "context_servers" ] { } cfg.userSettings;
  mergedMcpServers = transformedMcpServers // settingMcpServers;

  mergedSettings =
    cfg.userSettings
    // (lib.optionalAttrs (builtins.length cfg.extensions > 0) {
      # this part by @cmacrae
      auto_install_extensions = lib.genAttrs cfg.extensions (_: true);
    })
    // (lib.optionalAttrs (mergedMcpServers != { }) {
      context_servers = mergedMcpServers;
    });

  # Files linked from the store instead of merged. The cleanup reads the
  # matching file entries, so both must use these conditions.
  immutableFiles = {
    settings = !cfg.mutableUserSettings && mergedSettings != { };
    keymap = !cfg.mutableUserKeymaps && cfg.userKeymaps != [ ];
    tasks = !cfg.mutableUserTasks && cfg.userTasks != [ ];
    debug = !cfg.mutableUserDebug && cfg.userDebug != [ ];
  };

  immutableConfigCleanup = lib.concatMapStrings (
    name:
    lib.hm.generators.mkImpureConfigCleanup {
      file = config.home.file."${config.xdg.configHome}/zed/${name}.json";
    }
  ) (lib.attrNames (lib.filterAttrs (_: lib.id) immutableFiles));

  modelSelections = [
    "default_model"
    "subagent_model"
    "inline_assistant_model"
    "commit_message_model"
    "thread_summary_model"
    "compaction_model"
  ];
  toolRules = [
    "always_allow"
    "always_deny"
    "always_confirm"
  ];
  labelledEntries = {
    enable = config.home.mutableSettings.removeDropped;
    maps = [
      {
        path = [ ];
        keys = [ "label" ];
        atomic = true;
      }
    ];
  };

  editorEnv = {
    EDITOR = "${cfg.package.meta.mainProgram} --wait";
    VISUAL = "${cfg.package.meta.mainProgram} --wait";
  };
in
{
  meta.maintainers = [
    lib.maintainers.alinnow
    lib.maintainers.zh4ngx
  ];

  options = {
    programs.zed-editor = {
      enable = lib.mkEnableOption "Zed, the high performance, multiplayer code editor from the creators of Atom and Tree-sitter";

      package = lib.mkPackageOption pkgs "zed-editor" { nullable = true; };

      extraPackages = mkOption {
        type = with types; listOf package;
        default = [ ];
        example = literalExpression "[ pkgs.nixd ]";
        description = "Extra packages available to Zed.";
      };

      mutableUserSettings = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = ''
          Whether user settings (settings.json) can be updated by zed.

          Declared settings are then merged into the file at activation. With
          [](#opt-home.mutableSettings.removeDropped), settings removed from
          the configuration are removed from the file unless Zed has changed
          them since. Themes, agent profiles and servers, model selections,
          context servers and the terminal shell are removed whole, with what
          Zed added to them, or kept whole if Zed changed a declared value;
          list entries Zed added are kept.
        '';
      };

      mutableUserKeymaps = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = ''
          Whether user keymaps (keymap.json) can be updated by zed.

          Declared keymaps are then merged into the file at activation, by
          context. With [](#opt-home.mutableSettings.removeDropped), bindings
          removed from the configuration are removed from the file unless Zed
          has changed them since, and a context left without bindings is
          removed.
        '';
      };

      mutableUserTasks = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = ''
          Whether user tasks (tasks.json) can be updated by zed.

          Declared tasks are then merged into the file at activation, by label.
          With [](#opt-home.mutableSettings.removeDropped), a task removed from
          the configuration is removed from the file unless one of its declared
          values has changed since.
        '';
      };

      mutableUserDebug = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = ''
          Whether user debug configurations (debug.json) can be updated by zed.

          Declared configurations are then merged into the file at activation,
          by label. With [](#opt-home.mutableSettings.removeDropped), a
          configuration removed from the Home Manager configuration is removed
          from the file unless one of its declared values has changed since.
        '';
      };

      userSettings = mkOption {
        inherit (jsonFormat) type;
        default = { };
        example = {
          features = {
            copilot = false;
          };
          telemetry = {
            metrics = false;
          };
          vim_mode = false;
          ui_font_size = 16;
          buffer_font_size = 16;
        };
        description = ''
          Configuration written to Zed's {file}`settings.json`.
        '';
      };

      userKeymaps = mkOption {
        inherit (jsonFormat) type;
        default = [ ];
        example = literalExpression ''
          [
            {
              context = "Workspace";
              bindings = {
                ctrl-shift-t = "workspace::NewTerminal";
              };
            };
          ]
        '';
        description = ''
          Configuration written to Zed's {file}`keymap.json`.
        '';
      };

      userTasks = mkOption {
        inherit (jsonFormat) type;
        default = [ ];
        example = [
          {
            label = "Format Code";
            command = "nix";
            args = [
              "fmt"
              "$ZED_WORKTREE_ROOT"
            ];
          }
        ];
        description = ''
          Configuration written to Zed's {file}`tasks.json`.

          [List of tasks](https://zed.dev/docs/tasks) that can be run from the
          command palette.
        '';
      };

      userDebug = mkOption {
        inherit (jsonFormat) type;
        default = [ ];
        example = [
          {
            label = "Go (Delve)";
            adapter = "Delve";
            program = "$ZED_FILE";
            request = "launch";
            mode = "debug";
          }
        ];
        description = ''
          Configuration written to Zed's {file}`debug.json`.

          Global debug configurations for Zed's [Debugger](https://zed.dev/docs/debugger).
        '';
      };

      extensions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "swift"
          "nix"
          "xy-zed"
        ];
        description = ''
          A list of the extensions Zed should install on startup.
          Use the name of a repository in the [extension list](https://github.com/zed-industries/extensions/tree/main/extensions).
        '';
      };

      installRemoteServer = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to symlink the Zed's remote server binary to the expected
          location. This allows remotely connecting to this system from a
          distant Zed client.

          For more information, consult the
          ["Remote Server" section](https://wiki.nixos.org/wiki/Zed#Remote_Server)
          in the wiki.
        '';
      };

      enableMcpIntegration = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to integrate the MCP server config from
          {option}`programs.mcp.servers` into
          {option}`programs.zed-editor.userSettings.context_servers`.

          Note: Settings defined in {option}`programs.zed-editor.userSettings.context_servers`
          will take precedence over the generated MCP configuration.
        '';
      };

      themes = mkOption {
        description = ''
          Each theme is written to
          {file}`$XDG_CONFIG_HOME/zed/themes/theme-name.json`
          where the name of each attribute is the theme-name

          See <https://zed.dev/docs/extensions/themes> for the structure of a
          Zed theme
        '';
        type = types.attrsOf (
          types.oneOf [
            jsonFormat.type
            types.path
            types.lines
          ]
        );
        default = { };
      };

      defaultEditor = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to set {command}`zeditor -w` as the default editor using the
          {env}`EDITOR` and {env}`VISUAL` environment variables.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.extraPackages != [ ] -> cfg.package != null;
        message = "{option}programs.zed-editor.extraPackages requires non null {option}programs.zed-editor.package";
      }
      {
        assertion = cfg.defaultEditor -> cfg.package != null;
        message = "{option}programs.zed-editor.defaultEditor requires non null {option}programs.zed-editor.package";
      }
    ];

    home.packages = mkIf (cfg.package != null) (
      if cfg.extraPackages != [ ] then
        [
          (pkgs.symlinkJoin {
            name = "${lib.getName cfg.package}-wrapped-${lib.getVersion cfg.package}";
            paths = [ cfg.package ];
            preferLocalBuild = true;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/${cfg.package.meta.mainProgram or "zeditor"} \
                --suffix PATH : ${lib.makeBinPath cfg.extraPackages}
            '';
          })
        ]
      else
        [ cfg.package ]
    );

    home.file = mkIf (cfg.installRemoteServer && (cfg.package ? remote_server)) (
      let
        inherit (cfg.package) remote_server;
        binaryName = cfg.package.remoteServerExecutableName;
      in
      {
        ".zed_server/${binaryName}".source = lib.getExe' remote_server binaryName;
      }
    );

    home.activation = mkMerge [
      (mkIf (immutableConfigCleanup != "") {
        zedImmutableConfig =
          lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
            immutableConfigCleanup;
      })
      (mkIf cfg.mutableUserSettings {
        zedSettingsActivation = lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.hm.generators.mkImpureConfigMerger {
            inherit pkgs;
            format = "json";
            empty = "{}";
            # Zed records the profile picked in it as the default, which must
            # not outlive a profile removed from the configuration.
            jqOperation = ''
              ($dynamic * $static)
              | (.agent.default_profile? // null) as $profile
              | if ($profile | type) == "string"
                  and (any("write", "ask", "minimal"; . == $profile) | not)
                  and ($previous.agent.profiles? // {} | has($profile))
                  and (.agent.profiles? // {} | has($profile) | not)
                then
                  del(.agent.default_profile) | if .agent == {} then del(.agent) else . end
                else
                  .
                end
            '';
            path = "${config.xdg.configHome}/zed/settings.json";
            staticSettings = jsonFormat.generate "zed-user-settings" mergedSettings;
            reader = "${lib.getExe json5} --as-json";
            removal = {
              enable = config.home.mutableSettings.removeDropped;
              # Zed rejects these without their declared keys, for example a
              # profile without `name`, a model without `provider` or a theme
              # with only one of `light` and `dark`; a context server left
              # with only `enabled` is taken for an extension's and never
              # starts.
              atomic =
                map (key: [
                  "agent"
                  key
                ]) modelSelections
                ++ [
                  [ "theme" ]
                  [ "icon_theme" ]
                  [
                    "agent"
                    "profiles"
                    "*"
                  ]
                  [
                    "agent"
                    "profiles"
                    "*"
                    "default_model"
                  ]
                  [
                    "agent_servers"
                    "*"
                  ]
                  [
                    "context_servers"
                    "*"
                  ]
                  [
                    "terminal"
                    "shell"
                  ]
                ];
              sets = [
                [ "ssh_connections" ]
                [
                  "agent"
                  "favorite_models"
                ]
                [
                  "agent"
                  "inline_alternatives"
                ]
                [
                  "agent"
                  "sandbox_permissions"
                  "network_hosts"
                ]
                [
                  "agent"
                  "sandbox_permissions"
                  "write_paths"
                ]
              ]
              ++ map (rules: [
                "agent"
                "tool_permissions"
                "tools"
                "*"
                rules
              ]) toolRules;
            };
          }
        );
      })
      (mkIf cfg.mutableUserKeymaps {
        zedKeymapActivation = lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.hm.generators.mkImpureConfigMerger {
            inherit pkgs;
            format = "json";
            empty = "[]";
            jqOperation = "$dynamic + $static | group_by(.context) | map(reduce .[] as \$item ({}; . * \$item))";
            path = "${config.xdg.configHome}/zed/keymap.json";
            staticSettings = jsonFormat.generate "zed-user-keymaps" cfg.userKeymaps;
            reader = "${lib.getExe json5} --as-json";
            removal = {
              enable = config.home.mutableSettings.removeDropped;
              maps = [
                {
                  path = [ ];
                  keys = [ "context" ];
                }
              ];
            };
          }
        );
      })
      (mkIf cfg.mutableUserTasks {
        zedTasksActivation = lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.hm.generators.mkImpureConfigMerger {
            inherit pkgs;
            format = "json";
            empty = "[]";
            jqOperation = "$dynamic + $static | group_by(.label) | map(reduce .[] as \$item ({}; . * \$item))";
            path = "${config.xdg.configHome}/zed/tasks.json";
            staticSettings = jsonFormat.generate "zed-user-tasks" cfg.userTasks;
            reader = "${lib.getExe json5} --as-json";
            removal = labelledEntries;
          }
        );
      })
      (mkIf cfg.mutableUserDebug {
        zedDebugActivation = lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.hm.generators.mkImpureConfigMerger {
            inherit pkgs;
            format = "json";
            empty = "[]";
            jqOperation = "$dynamic + $static | group_by(.label) | map(reduce .[] as \$item ({}; . * \$item))";
            path = "${config.xdg.configHome}/zed/debug.json";
            staticSettings = jsonFormat.generate "zed-user-debug" cfg.userDebug;
            reader = "${lib.getExe json5} --as-json";
            removal = labelledEntries;
          }
        );
      })
    ];

    xdg.configFile = mkMerge [
      (lib.mapAttrs' (
        n: v:
        lib.nameValuePair "zed/themes/${n}.json" {
          source =
            if lib.isString v then
              pkgs.writeText "zed-theme-${n}" v
            else if builtins.isPath v || lib.isStorePath v then
              v
            else
              jsonFormat.generate "zed-theme-${n}" v;
        }
      ) cfg.themes)
      (mkIf immutableFiles.settings {
        "zed/settings.json".source = jsonFormat.generate "zed-user-settings" mergedSettings;
      })
      (mkIf immutableFiles.keymap {
        "zed/keymap.json".source = jsonFormat.generate "zed-user-keymaps" cfg.userKeymaps;
      })
      (mkIf immutableFiles.tasks {
        "zed/tasks.json".source = jsonFormat.generate "zed-user-tasks" cfg.userTasks;
      })
      (mkIf immutableFiles.debug {
        "zed/debug.json".source = jsonFormat.generate "zed-user-debug" cfg.userDebug;
      })
    ];

    home.sessionVariables = mkIf cfg.defaultEditor editorEnv;
  };
}
