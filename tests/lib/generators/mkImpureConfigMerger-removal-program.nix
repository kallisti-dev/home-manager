{ lib, pkgs, ... }:

# The removal program on its own. Each case removes from `current` the
# settings of `previous` that `static` no longer declares, by `rules` in the
# form the merger passes them, and expects `expected`, in key order. Values
# given as JSON text keep the order they are written in.
let
  jaq = lib.getExe pkgs.jaq;
  program = ../../../modules/lib/impure-config-removal.jq;

  json =
    name: value:
    builtins.toFile "${name}.json" (if builtins.isString value then value else builtins.toJSON value);

  servers = {
    atomic = [
      [
        "servers"
        "*"
      ]
    ];
  };
  allow = {
    sets = [
      {
        path = [ "allow" ];
        keep = [ ];
      }
    ];
  };
  rules = {
    sets = [
      {
        path = [ "rules" ];
        keep = [ "$defaults" ];
      }
    ];
  };
  mcp = {
    maps = [
      {
        path = [ "servers" ];
        keys = [ "name" ];
        atomic = false;
      }
    ];
  };
  tasks = {
    maps = [
      {
        path = [ "tasks" ];
        keys = [ "label" ];
        atomic = true;
      }
    ];
  };
  keymap = {
    maps = [
      {
        path = [ ];
        keys = [ "context" ];
        atomic = false;
      }
    ];
  };

  cases = {
    # Leaves go while they equal the recorded value; declared values and
    # values the application added stay.
    leaf-dropped = {
      previous = {
        theme = "dark";
        editor = {
          fontSize = 12;
          tabSize = 2;
        };
        kept = true;
      };
      static = {
        editor.fontSize = 12;
        kept = true;
      };
      current = {
        theme = "dark";
        editor = {
          fontSize = 12;
          tabSize = 2;
          lineNumbers = true;
        };
        kept = true;
        app = 1;
      };
      expected = {
        editor = {
          fontSize = 12;
          lineNumbers = true;
        };
        kept = true;
        app = 1;
      };
    };
    leaf-changed = {
      previous = {
        theme = "dark";
        size = 1;
      };
      static = { };
      current = {
        theme = "light";
        size = 1;
      };
      expected.theme = "light";
    };
    leaf-null = {
      previous = {
        nothing = null;
        nested.deep.leaf = null;
        kept = true;
      };
      static.kept = true;
      current = {
        nothing = null;
        nested.deep.leaf = null;
        kept = true;
      };
      expected.kept = true;
    };
    leaf-null-replaced = {
      previous.nothing = null;
      static = { };
      current.nothing = 5;
      expected.nothing = 5;
    };
    # An array without a rule is a leaf.
    leaf-array = {
      previous = {
        hooks = [ { command = "a"; } ];
        list = [
          1
          2
        ];
      };
      static = { };
      current = {
        hooks = [ { command = "b"; } ];
        list = [
          1
          2
        ];
      };
      expected.hooks = [ { command = "b"; } ];
    };
    leaf-special-keys = {
      previous = {
        "*".star = true;
        "a.b" = 1;
        "c/d" = 2;
        "e f" = 3;
        "ü" = 4;
        kept = true;
      };
      static.kept = true;
      current = {
        "*".star = true;
        "a.b" = 1;
        "c/d" = 2;
        "e f" = 3;
        "ü" = 4;
        kept = true;
      };
      expected.kept = true;
    };

    # An object goes once the removal emptied it, including a declared empty
    # object that was dropped; one the application emptied or replaced, or
    # that is still declared, stays.
    object-emptied = {
      previous = {
        editor.tabSize = 2;
        marker = { };
      };
      static = { };
      current = {
        editor.tabSize = 2;
        marker = { };
        app = 1;
      };
      expected.app = 1;
    };
    object-app-keys = {
      previous.permissions.allow = [ "Read" ];
      static = { };
      current.permissions = {
        allow = [ "Read" ];
        defaultMode = "plan";
      };
      expected.permissions.defaultMode = "plan";
    };
    object-emptied-by-app = {
      previous.editor.tabSize = 2;
      static = { };
      current.editor = { };
      expected.editor = { };
    };
    object-declared = {
      previous.editor.tabSize = 2;
      static.editor = { };
      current.editor.tabSize = 2;
      expected.editor = { };
    };
    object-replaced = {
      previous.editor.tabSize = 2;
      static = { };
      current.editor = "vim";
      expected.editor = "vim";
    };
    object-order = {
      previous = ''{"b": 1}'';
      static = "{}";
      current = ''{"c": 3, "b": 1, "a": 1}'';
      expected = ''{"c": 3, "a": 1}'';
    };

    # An atomic value goes whole, with the keys the application added, unless
    # a recorded value in it changed. A recorded key the application deleted
    # does not count; a recorded object replaced by another type does. While
    # declared, an atomic value loses only the dropped values.
    atomic-dropped = {
      rules = servers;
      previous.servers = {
        plain.command = "a";
        annotated.command = "b";
      };
      static = { };
      current = {
        servers = {
          plain.command = "a";
          annotated = {
            command = "b";
            enabled = true;
          };
        };
        app = 1;
      };
      expected.app = 1;
    };
    atomic-changed = {
      rules = servers;
      previous.servers.changed.command = "c";
      static = { };
      current.servers.changed = {
        command = "user";
        enabled = true;
      };
      expected.servers.changed = {
        command = "user";
        enabled = true;
      };
    };
    atomic-deleted-key = {
      rules = servers;
      previous.servers.migrated = {
        command = "d";
        config.enabled = true;
      };
      static = { };
      current.servers.migrated = {
        command = "d";
        enabled = true;
      };
      expected = { };
    };
    atomic-deleted-null = {
      rules = servers;
      previous.servers.a = {
        command = "x";
        cwd = null;
      };
      static = { };
      current.servers.a.command = "x";
      expected = { };
    };
    atomic-null-set = {
      rules = servers;
      previous.servers.a = {
        command = "x";
        cwd = null;
      };
      static = { };
      current.servers.a = {
        command = "x";
        cwd = "/";
      };
      expected.servers.a = {
        command = "x";
        cwd = "/";
      };
    };
    atomic-declared = {
      rules = servers;
      previous.servers.partial = {
        command = "e";
        env.TOKEN = "t";
      };
      static.servers.partial.command = "e";
      current.servers.partial = {
        command = "e";
        env.TOKEN = "t";
        enabled = true;
      };
      expected.servers.partial = {
        command = "e";
        enabled = true;
      };
    };
    atomic-replaced-by-string = {
      rules.atomic = [ [ "theme" ] ];
      previous.theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };
      static = { };
      current.theme = "Solarized Dark";
      expected.theme = "Solarized Dark";
    };
    atomic-replaced-by-null = {
      rules.atomic = [ [ "theme" ] ];
      previous.theme.mode = "system";
      static = { };
      current.theme = null;
      expected.theme = null;
    };
    atomic-replaced-by-array = {
      rules.atomic = [ [ "theme" ] ];
      previous.theme.mode = "system";
      static = { };
      current.theme = [ "One Dark" ];
      expected.theme = [ "One Dark" ];
    };
    atomic-nested-replaced = {
      rules = servers;
      previous.servers.a = {
        command = "x";
        env.A = "1";
      };
      static = { };
      current.servers.a = {
        command = "x";
        env = "none";
      };
      expected.servers.a = {
        command = "x";
        env = "none";
      };
    };

    keep = {
      rules.keep = [
        [
          "vaults"
          "*"
        ]
      ];
      previous = {
        vaults.notes.path = "/notes";
        other = 1;
      };
      static = { };
      current = {
        vaults.notes = {
          path = "/notes";
          ts = 1;
        };
        other = 1;
      };
      expected.vaults.notes = {
        path = "/notes";
        ts = 1;
      };
    };

    # From a set, recorded elements that are neither declared nor protected
    # go; elements the application added stay. A set goes once the removal
    # emptied it or it is still the recorded empty set, unless declared; one
    # the application emptied stays.
    set-dropped = {
      rules = allow;
      previous.allow = [
        "Read"
        "Bash"
      ];
      static.allow = [ "Read" ];
      current.allow = [
        "Read"
        "Bash"
        "Edit"
      ];
      expected.allow = [
        "Read"
        "Edit"
      ];
    };
    set-emptied = {
      rules = allow;
      previous.allow = [ "Read" ];
      static = { };
      current = {
        allow = [ "Read" ];
        app = 1;
      };
      expected.app = 1;
    };
    set-declared-emptied = {
      rules = allow;
      previous.allow = [ "Read" ];
      static.allow = [ ];
      current.allow = [ "Read" ];
      expected.allow = [ ];
    };
    set-emptied-by-app = {
      rules = allow;
      previous.allow = [ "Read" ];
      static = { };
      current.allow = [ ];
      expected.allow = [ ];
    };
    set-recorded-empty = {
      rules = allow;
      previous.allow = [ ];
      static = { };
      current = {
        allow = [ ];
        app = 1;
      };
      expected.app = 1;
    };
    set-protected = {
      inherit rules;
      previous.rules = [
        "$defaults"
        "declared"
      ];
      static = { };
      current.rules = [
        "$defaults"
        "declared"
        "app"
      ];
      expected.rules = [
        "$defaults"
        "app"
      ];
    };
    set-protected-last = {
      inherit rules;
      previous.rules = [
        "$defaults"
        "declared"
      ];
      static = { };
      current = {
        rules = [
          "$defaults"
          "declared"
        ];
        app = 1;
      };
      expected.app = 1;
    };
    set-emptied-parent = {
      rules.sets = [
        {
          path = [
            "permissions"
            "allow"
          ];
          keep = [ ];
        }
      ];
      previous.permissions.allow = [ "Read" ];
      static = { };
      current = {
        permissions.allow = [ "Read" ];
        app = 1;
      };
      expected.app = 1;
    };
    # Set and map rules apply to recorded arrays only.
    set-not-array = {
      rules = allow;
      previous.allow = "all";
      static = { };
      current = {
        allow = "all";
        app = 1;
      };
      expected.app = 1;
    };

    # Elements of a keyed array lose the recorded values and keep their key
    # fields and what the application added; one left with only its key
    # fields goes. Elements without a recorded counterpart stay.
    map-dropped-values = {
      rules = mcp;
      previous.servers = [
        {
          name = "a";
          command = "x";
          args = [ "1" ];
        }
      ];
      static.servers = [
        {
          name = "a";
          command = "x";
        }
      ];
      current.servers = [
        {
          name = "a";
          command = "x";
          args = [ "1" ];
          enabled = true;
        }
      ];
      expected.servers = [
        {
          name = "a";
          command = "x";
          enabled = true;
        }
      ];
    };
    map-keys-only = {
      rules = mcp;
      previous.servers = [
        {
          name = "a";
          command = "x";
        }
      ];
      static = { };
      current.servers = [
        {
          name = "a";
          command = "x";
        }
        {
          name = "user";
          command = "y";
        }
        "junk"
      ];
      expected.servers = [
        {
          name = "user";
          command = "y";
        }
        "junk"
      ];
    };
    map-emptied = {
      rules = mcp;
      previous.servers = [
        {
          name = "a";
          command = "x";
        }
      ];
      static = { };
      current = {
        servers = [
          {
            name = "a";
            command = "x";
          }
        ];
        app = 1;
      };
      expected.app = 1;
    };
    map-duplicates = {
      rules = mcp;
      previous.servers = [
        {
          name = "a";
          command = "x";
        }
        {
          name = "a";
          args = [ "1" ];
        }
      ];
      static = { };
      current.servers = [
        {
          name = "a";
          command = "x";
          args = [ "1" ];
          enabled = true;
        }
      ];
      expected.servers = [
        {
          name = "a";
          enabled = true;
        }
      ];
    };
    map-compound-key = {
      rules.maps = [
        {
          path = [ "bindings" ];
          keys = [
            "key"
            "when"
          ];
          atomic = false;
        }
      ];
      previous.bindings = [
        {
          key = "a";
          when = "x";
          command = "c1";
        }
        {
          key = "a";
          when = "y";
          command = "c2";
        }
      ];
      static.bindings = [
        {
          key = "a";
          when = "y";
          command = "c2";
        }
      ];
      current.bindings = [
        {
          key = "a";
          when = "x";
          command = "c1";
        }
        {
          key = "a";
          when = "y";
          command = "c2";
        }
      ];
      expected.bindings = [
        {
          key = "a";
          when = "y";
          command = "c2";
        }
      ];
    };
    # Atomic elements go whole unless a recorded value changed; a declared
    # one loses only the dropped values.
    map-atomic = {
      rules = tasks;
      previous.tasks = [
        {
          label = "build";
          command = "make";
        }
        {
          label = "test";
          command = "make test";
        }
        {
          label = "lint";
          command = "lint";
        }
      ];
      static.tasks = [
        {
          label = "lint";
          command = "lint";
        }
      ];
      current.tasks = [
        {
          label = "build";
          command = "make";
          env.A = "1";
        }
        {
          label = "test";
          command = "user";
        }
        {
          label = "lint";
          command = "lint";
        }
        {
          label = "mine";
          command = "x";
        }
      ];
      expected.tasks = [
        {
          label = "test";
          command = "user";
        }
        {
          label = "lint";
          command = "lint";
        }
        {
          label = "mine";
          command = "x";
        }
      ];
    };
    map-atomic-declared = {
      rules = tasks;
      previous.tasks = [
        {
          label = "build";
          command = "make";
          env.A = "1";
        }
      ];
      static.tasks = [
        {
          label = "build";
          command = "make";
        }
      ];
      current.tasks = [
        {
          label = "build";
          command = "make";
          env.A = "1";
          tags = [ "x" ];
        }
      ];
      expected.tasks = [
        {
          label = "build";
          command = "make";
          tags = [ "x" ];
        }
      ];
    };
    map-atomic-replaced = {
      rules = tasks;
      previous.tasks = [
        {
          label = "build";
          env.A = "1";
        }
      ];
      static = { };
      current.tasks = [
        {
          label = "build";
          env = "none";
        }
      ];
      expected.tasks = [
        {
          label = "build";
          env = "none";
        }
      ];
    };

    # The whole file is declared while any setting is. Removing it leaves the
    # empty object or array.
    root-atomic-dropped = {
      rules.atomic = [ [ ] ];
      previous.command = "server-a";
      static = { };
      current = {
        command = "server-a";
        enabled = true;
      };
      expected = { };
    };
    root-atomic-changed = {
      rules.atomic = [ [ ] ];
      previous.command = "server-a";
      static = { };
      current = {
        command = "user";
        enabled = true;
      };
      expected = {
        command = "user";
        enabled = true;
      };
    };
    root-atomic-declared = {
      rules.atomic = [ [ ] ];
      previous = {
        command = "server-a";
        args = [ ];
      };
      static.command = "server-a";
      current = {
        command = "server-a";
        args = [ ];
        enabled = true;
      };
      expected = {
        command = "server-a";
        enabled = true;
      };
    };
    root-keep = {
      rules.keep = [ [ ] ];
      previous.a = 1;
      static = { };
      current.a = 1;
      expected.a = 1;
    };
    root-set = {
      rules.sets = [
        {
          path = [ ];
          keep = [ ];
        }
      ];
      previous = [
        "a"
        "b"
      ];
      static = [ "a" ];
      current = [
        "a"
        "b"
        "c"
      ];
      expected = [
        "a"
        "c"
      ];
    };
    root-set-emptied = {
      rules.sets = [
        {
          path = [ ];
          keep = [ ];
        }
      ];
      previous = [ "a" ];
      static = [ ];
      current = [ "a" ];
      expected = [ ];
    };
    root-map = {
      rules = keymap;
      previous = [
        {
          context = "Editor";
          bindings = {
            a = "x";
            b = "y";
          };
        }
        {
          context = "Pane";
          bindings.p = "q";
        }
        { bindings.g = "h"; }
      ];
      static = [
        {
          context = "Editor";
          bindings.a = "x";
        }
      ];
      current = [
        {
          context = "Editor";
          bindings = {
            a = "x";
            b = "y";
            u = "user";
          };
        }
        {
          context = "Pane";
          bindings.p = "q";
        }
        { bindings.g = "h"; }
      ];
      expected = [
        {
          context = "Editor";
          bindings = {
            a = "x";
            u = "user";
          };
        }
      ];
    };
    root-map-emptied = {
      rules = keymap;
      previous = [
        {
          context = "Editor";
          bindings.a = "x";
        }
      ];
      static = [ ];
      current = [
        {
          context = "Editor";
          bindings.a = "x";
        }
      ];
      expected = [ ];
    };
    root-array-declared = {
      previous = [ "a" ];
      static = [ "b" ];
      current = [ "a" ];
      expected = [ "a" ];
    };
    root-array-dropped = {
      previous = [ "a" ];
      static = [ ];
      current = [ "a" ];
      expected = [ ];
    };
    root-object-dropped = {
      previous.a = 1;
      static = { };
      current.a = 1;
      expected = { };
    };

    # keep takes precedence over set and atomic rules, and set over atomic.
    precedence-keep-set = {
      rules = allow // {
        keep = [ [ "allow" ] ];
      };
      previous.allow = [ "Read" ];
      static = { };
      current.allow = [ "Read" ];
      expected.allow = [ "Read" ];
    };
    precedence-keep-atomic = {
      rules = servers // {
        keep = [
          [
            "servers"
            "*"
          ]
        ];
      };
      previous.servers.a.command = "x";
      static = { };
      current.servers.a.command = "x";
      expected.servers.a.command = "x";
    };
    precedence-set-atomic = {
      rules = allow // {
        atomic = [ [ "allow" ] ];
      };
      previous.allow = [
        "Read"
        "Bash"
      ];
      static = { };
      current.allow = [
        "Read"
        "Bash"
        "Edit"
      ];
      expected.allow = [ "Edit" ];
    };
  };

  check =
    name: case:
    let
      rules = {
        keep = [ ];
        atomic = [ ];
        sets = [ ];
        maps = [ ];
      }
      // (case.rules or { });
    in
    ''
      check ${lib.escapeShellArg name} \
        ${json "${name}-previous" case.previous} \
        ${json "${name}-static" case.static} \
        ${json "${name}-current" case.current} \
        ${json "${name}-expected" case.expected} \
        ${lib.escapeShellArg (builtins.toJSON rules)}
    '';
in
{
  nmt.script = ''
    check() {
      actual="$(${jaq} -c -f ${program} --argjson rules "$6" --slurpfile previous "$2" --slurpfile static "$3" "$4")" \
        || fail "$1: the removal failed"
      expected="$(${jaq} -c . "$5")"
      [[ "$actual" == "$expected" ]] || fail "$1: expected $expected, got $actual"
    }
    ${lib.concatStrings (lib.mapAttrsToList check cases)}
  '';
}
