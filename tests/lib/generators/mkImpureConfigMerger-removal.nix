{ lib, pkgs, ... }:

let
  jaq = lib.getExe pkgs.jaq;

  mkScript =
    name: options:
    pkgs.writeScript name ''
      set -euo pipefail
      errorEcho() { echo "$*" >&2; }
      warnEcho() { echo "$*" >&2; }
      ${lib.hm.generators.mkImpureConfigMerger (
        {
          inherit pkgs;
          format = "json";
          empty = "{}";
          jqOperation = "$dynamic * $static";
          path = "/@TMPDIR@/merger-removal/settings.json";
          removal.enable = true;
        }
        // options
      )}
    '';
  mkGeneration =
    name: settings: options:
    mkScript name (
      {
        staticSettings = builtins.toFile "${name}.json" (builtins.toJSON settings);
      }
      // options
    );

  firstSettings = {
    theme = "dark";
    hooks.SessionStart = [ { command = "/nix/store/hook"; } ];
    editor = {
      fontSize = 12;
      tabSize = 2;
    };
    permissions.allow = [ "Read" ];
    marker = { };
    kept = true;
  };
  secondSettings = {
    editor.fontSize = 12;
    kept = true;
  };
  first = mkGeneration "first" firstSettings { };
  second = mkGeneration "second" secondSettings { };
  emptied = mkGeneration "emptied" { } { };
  failingSecond = mkGeneration "failing-second" secondSettings {
    jqOperation = ''error("merge failed")'';
  };
  disabledFirst = mkGeneration "disabled-first" firstSettings { removal = { }; };
  disabledSecond = mkGeneration "disabled-second" secondSettings { removal = { }; };
  disabledEmptied = mkGeneration "disabled-emptied" { } { removal = { }; };

  strategies = {
    removal = {
      enable = true;
      atomic = [
        [
          "servers"
          "*"
        ]
      ];
      keep = [
        [
          "vaults"
          "*"
        ]
      ];
      sets = [
        [ "allow" ]
        [ "ask" ]
        [ "deny" ]
        {
          path = [ "rules" ];
          keep = [ "$defaults" ];
        }
        {
          path = [ "defaultRules" ];
          keep = [ "$defaults" ];
        }
      ];
    };
    path = "/@TMPDIR@/merger-removal/strategies.json";
  };
  firstStrategies = mkGeneration "first-strategies" {
    servers = {
      plain.command = "a";
      annotated.command = "b";
      changed.command = "c";
      migrated = {
        command = "d";
        config.enabled = true;
      };
      partial = {
        command = "e";
        env.TOKEN = "t";
      };
    };
    vaults.notes.path = "/notes";
    allow = [
      "Read"
      "Bash"
    ];
    ask = [ "Write" ];
    deny = [ ];
    rules = [
      "$defaults"
      "declared"
    ];
    defaultRules = [
      "$defaults"
      "declared"
    ];
  } strategies;
  secondStrategies = mkGeneration "second-strategies" {
    servers.partial.command = "e";
  } strategies;

  foldersOperation = ''
    if $static | has("folders") then
      $dynamic + {folders: (($dynamic.folders // []) as $have | $have + ($static.folders - $have))}
    else
      $dynamic
    end
  '';
  mkFolders =
    name: settings:
    mkGeneration name settings {
      jqOperation = foldersOperation;
      path = "/@TMPDIR@/merger-removal/folders.json";
      removal = {
        enable = true;
        sets = [ [ "folders" ] ];
      };
    };
  firstFolders = mkFolders "first-folders" {
    folders = [
      "/a"
      "/b"
    ];
  };
  secondFolders = mkFolders "second-folders" { folders = [ "/a" ]; };
  emptiedFolders = mkFolders "emptied-folders" { };

  mkKeymap =
    name: settings:
    mkGeneration name settings {
      jqOperation = "$dynamic + $static | group_by(.context) | map(reduce .[] as $item ({}; . * $item))";
      path = "/@TMPDIR@/merger-removal/keymap.json";
      empty = "[]";
      removal = {
        enable = true;
        maps = [
          {
            path = [ ];
            keys = [ "context" ];
          }
        ];
      };
    };
  firstKeymap = mkKeymap "first-keymap" [
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
  secondKeymap = mkKeymap "second-keymap" [
    {
      context = "Editor";
      bindings.a = "x";
    }
  ];
  emptiedKeymap = mkKeymap "emptied-keymap" [ ];

  mkTasks =
    name: settings:
    mkGeneration name settings {
      jqOperation = "$dynamic + $static | group_by(.label) | map(reduce .[] as $item ({}; . * $item))";
      path = "/@TMPDIR@/merger-removal/tasks.json";
      empty = "[]";
      removal = {
        enable = true;
        maps = [
          {
            path = [ ];
            keys = [ "label" ];
            atomic = true;
          }
        ];
      };
    };
  firstTasks = mkTasks "first-tasks" [
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
  secondTasks = mkTasks "second-tasks" [
    {
      label = "lint";
      command = "lint";
    }
  ];

  mkPrevious =
    name: settings: removal:
    mkGeneration name settings {
      inherit removal;
      jqOperation = "$dynamic * $static | .previous = $previous";
      path = "/@TMPDIR@/merger-removal/previous.json";
    };
  firstPrevious = mkPrevious "first-previous" { a = 1; } { enable = true; };
  secondPrevious = mkPrevious "second-previous" { b = 2; } { enable = true; };
  disabledPrevious = mkPrevious "disabled-previous" { b = 2; } { };

  plainArray =
    name: settings:
    mkGeneration name settings {
      path = "/@TMPDIR@/merger-removal/plain-array.json";
      jqOperation = "$dynamic + $static | unique";
      empty = "[]";
    };
  firstPlainArray = plainArray "first-plain-array" [ "a" ];
  secondPlainArray = plainArray "second-plain-array" [ "b" ];

  mkEdge =
    name: settings: mkGeneration name settings { path = "/@TMPDIR@/merger-removal/edge.json"; };
  firstEdge = mkEdge "first-edge" {
    "*" = {
      star = true;
    };
    "a.b" = 1;
    "c/d" = 2;
    "e f" = 3;
    "ü" = 4;
    nothing = null;
    nested.deep.leaf = null;
    kept = true;
  };
  secondEdge = mkEdge "second-edge" { kept = true; };

  mkToml =
    name: text:
    mkScript name {
      format = "toml";
      path = "/@TMPDIR@/merger-removal/settings.toml";
      staticSettings = builtins.toFile "${name}.toml" text;
    };
  firstToml = mkToml "first-toml" "a = 1\nb = 2\n";
  secondToml = mkToml "second-toml" "a = 1\n";
in
{
  nmt.script = ''
    for script in ${first} ${second} ${emptied} ${failingSecond} \
      ${disabledFirst} ${disabledSecond} ${disabledEmptied} \
      ${firstStrategies} ${secondStrategies} \
      ${firstFolders} ${secondFolders} ${emptiedFolders} \
      ${firstKeymap} ${secondKeymap} ${emptiedKeymap} ${firstTasks} ${secondTasks} \
      ${firstPrevious} ${secondPrevious} ${disabledPrevious} \
      ${firstPlainArray} ${secondPlainArray} ${firstEdge} ${secondEdge} \
      ${firstToml} ${secondToml}; do
      name="''${script#*-}"
      substitute "$script" "$TMPDIR/$name" --subst-var TMPDIR
      chmod +x "$TMPDIR/$name"
    done
    export XDG_STATE_HOME="$TMPDIR/state"
    directory="$TMPDIR/merger-removal"
    records="$XDG_STATE_HOME/home-manager/mutable-settings$directory"
    settings="$directory/settings.json"
    record="$records/settings.json.json"

    assertJson() {
      ${jaq} -e "$2" "$1" > /dev/null || fail "Expected $2 in $1, got $(cat "$1")"
    }
    assertRecord() {
      assertJson "$1" ". == {version: 1, static: $2}"
    }
    edit() {
      ${jaq} "$2" "$1" > "$TMPDIR/edited"
      cat "$TMPDIR/edited" > "$1"
    }
    reset() {
      rm -rf "$directory" "$XDG_STATE_HOME"
      mkdir -p "$directory"
    }

    # Without a record nothing is removed.
    reset
    echo '${builtins.toJSON firstSettings}' > "$settings"
    "$TMPDIR/second"
    assertJson "$settings" '.theme == "dark" and .hooks.SessionStart != null and .editor.tabSize == 2'
    assertRecord "$record" '${builtins.toJSON secondSettings}'
    # Settings dropped before the first record stay, and an unchanged record
    # is not rewritten.
    recordInode="$(stat -c '%i' "$record")"
    "$TMPDIR/second"
    assertJson "$settings" '.theme == "dark"'
    [[ "$(stat -c '%i' "$record")" == "$recordInode" ]] || fail "An unchanged record was rewritten"

    # Removed settings are deleted, including an emptied parent object and a
    # declared empty object. Keys the application added survive, including
    # those under a removed object.
    reset
    "$TMPDIR/first"
    assertRecord "$record" '${builtins.toJSON firstSettings}'
    edit "$settings" '.app = 1 | .permissions.defaultMode = "plan" | .editor.lineNumbers = true'
    "$TMPDIR/second"
    assertJson "$settings" '. == {
      editor: {fontSize: 12, lineNumbers: true},
      permissions: {defaultMode: "plan"},
      kept: true,
      app: 1
    }'
    assertRecord "$record" '${builtins.toJSON secondSettings}'

    # A value changed since it was applied is kept, an array as a whole; an
    # unchanged sibling is still removed.
    reset
    "$TMPDIR/first"
    edit "$settings" '.theme = "light" | .hooks.SessionStart[0].command = "/usr/bin/hook"'
    "$TMPDIR/second"
    assertJson "$settings" '. == {
      theme: "light",
      hooks: {SessionStart: [{command: "/usr/bin/hook"}]},
      editor: {fontSize: 12},
      kept: true
    }'

    # Removing the last setting removes what was recorded and then the
    # record. Without a record, empty settings neither create nor read the
    # file.
    reset
    "$TMPDIR/first"
    edit "$settings" '.app = 1'
    "$TMPDIR/emptied"
    assertJson "$settings" '. == {app: 1}'
    assertPathNotExists "$record"
    echo '{' > "$settings"
    "$TMPDIR/emptied"
    assertFileContent "$settings" ${builtins.toFile "broken.json" "{\n"}
    rm "$settings"
    "$TMPDIR/emptied"
    assertPathNotExists "$settings"
    # A record whose file is gone is dropped without creating the file.
    "$TMPDIR/first"
    rm "$settings"
    "$TMPDIR/emptied"
    assertPathNotExists "$settings"
    assertPathNotExists "$record"

    # With removal disabled, records are still kept, so enabling removal
    # affects only settings dropped afterwards.
    reset
    "$TMPDIR/disabled-first"
    "$TMPDIR/disabled-second"
    assertJson "$settings" '. == ${builtins.toJSON firstSettings}'
    assertRecord "$record" '${builtins.toJSON secondSettings}'
    "$TMPDIR/second"
    assertJson "$settings" '. == ${builtins.toJSON firstSettings}'
    "$TMPDIR/disabled-emptied"
    assertJson "$settings" '. == ${builtins.toJSON firstSettings}'
    assertPathNotExists "$record"

    # A dry run writes neither the file nor the record.
    reset
    DRY_RUN=1 "$TMPDIR/first" > /dev/null
    assertPathNotExists "$settings"
    assertPathNotExists "$record"

    # A failed merge keeps the record, so a later merge still removes what
    # the last successful one applied.
    reset
    "$TMPDIR/first"
    cp "$record" "$TMPDIR/first-record"
    echo '{' > "$settings"
    if "$TMPDIR/second" 2> /dev/null; then
      fail "Merging a malformed file must fail activation"
    fi
    assertFileContent "$record" "$TMPDIR/first-record"
    echo '${builtins.toJSON firstSettings}' > "$settings"
    if "$TMPDIR/failing-second" 2> /dev/null; then
      fail "A failing operation must fail activation"
    fi
    assertFileContent "$record" "$TMPDIR/first-record"
    "$TMPDIR/second"
    assertJson "$settings" '. == ${builtins.toJSON secondSettings}'

    # An unreadable record fails activation without changing the file.
    echo '{' > "$record"
    cp "$settings" "$TMPDIR/before-corrupt"
    if "$TMPDIR/first" 2> "$TMPDIR/corrupt.log"; then
      fail "An unreadable record must fail activation"
    fi
    assertFileContent "$settings" "$TMPDIR/before-corrupt"
    grep -qF "/merger-removal/settings.json.json'; refusing to merge" "$TMPDIR/corrupt.log" \
      || fail "The error must name the record"

    # A record without the current version is ignored, so nothing is removed
    # on that activation, and it is replaced.
    reset
    echo '${builtins.toJSON firstSettings}' > "$settings"
    mkdir -p "$records"
    echo '{"version": 2, "static": ${builtins.toJSON firstSettings}}' > "$record"
    "$TMPDIR/second"
    assertJson "$settings" '.theme == "dark" and .hooks.SessionStart != null'
    assertRecord "$record" '${builtins.toJSON secondSettings}'
    echo '${builtins.toJSON firstSettings}' > "$settings"
    echo '${builtins.toJSON firstSettings}' > "$record"
    "$TMPDIR/second"
    assertJson "$settings" '.theme == "dark"'
    assertRecord "$record" '${builtins.toJSON secondSettings}'
    echo '${builtins.toJSON firstSettings}' > "$settings"
    echo '{"version": 1, "static": "oops"}' > "$record"
    "$TMPDIR/second"
    assertJson "$settings" '.theme == "dark"'
    assertRecord "$record" '${builtins.toJSON secondSettings}'

    # An atomic entry goes whole, with the keys the application added, unless
    # a value Home Manager wrote in it has changed. A recorded value the
    # application deleted does not count as a change, and an entry that is
    # still declared loses only the dropped values. Kept values and set
    # elements the application added stay, and so does a set the application
    # emptied, while a recorded empty set goes. A protected element stays
    # while elements the application added remain.
    reset
    "$TMPDIR/first-strategies"
    edit "$directory/strategies.json" '
      .servers.annotated.enabled = true
      | .servers.changed.command = "user"
      | .servers.migrated |= (del(.config) | .enabled = true)
      | .servers.partial.enabled = true
      | .vaults.notes.ts = 1
      | .allow += ["Edit"]
      | .ask = []
      | .rules += ["app"]
    '
    "$TMPDIR/second-strategies"
    assertJson "$directory/strategies.json" '. == {
      servers: {changed: {command: "user"}, partial: {command: "e", enabled: true}},
      vaults: {notes: {path: "/notes", ts: 1}},
      allow: ["Edit"],
      ask: [],
      rules: ["$defaults", "app"]
    }'

    # Set elements are removed even when the operation unions the array.
    reset
    echo '{"login": true, "folders": ["/user"]}' > "$directory/folders.json"
    "$TMPDIR/first-folders"
    assertJson "$directory/folders.json" '.folders == ["/user", "/a", "/b"]'
    "$TMPDIR/second-folders"
    assertJson "$directory/folders.json" '. == {login: true, folders: ["/user", "/a"]}'
    "$TMPDIR/emptied-folders"
    assertJson "$directory/folders.json" '. == {login: true, folders: ["/user"]}'

    # Keyed elements lose the recorded values, keep their keys and the
    # values the application added, and go once only their keys are left.
    "$TMPDIR/first-keymap"
    edit "$directory/keymap.json" '. + [{context: "Editor", bindings: {u: "user"}}]'
    "$TMPDIR/first-keymap"
    "$TMPDIR/second-keymap"
    assertJson "$directory/keymap.json" '. == [{context: "Editor", bindings: {a: "x", u: "user"}}]'
    "$TMPDIR/emptied-keymap"
    assertJson "$directory/keymap.json" '. == [{context: "Editor", bindings: {u: "user"}}]'

    # Atomic keyed elements go whole unless a recorded value changed.
    "$TMPDIR/first-tasks"
    edit "$directory/tasks.json" '
      map(if .label == "build" then .env = {A: "1"} elif .label == "test" then .command = "user" else . end)
      + [{label: "mine", command: "x"}]
    '
    "$TMPDIR/second-tasks"
    assertJson "$directory/tasks.json" '. == [
      {label: "lint", command: "lint"},
      {label: "mine", command: "x"},
      {label: "test", command: "user"}
    ]'

    # The operation sees the record as $previous while removal is enabled.
    "$TMPDIR/first-previous"
    assertJson "$directory/previous.json" '. == {a: 1, previous: null}'
    "$TMPDIR/second-previous"
    assertJson "$directory/previous.json" '. == {b: 2, previous: {a: 1}}'
    "$TMPDIR/disabled-previous"
    assertJson "$directory/previous.json" '.previous == null'

    # An array without a rule is removed only as a whole, so a root array
    # keeps its elements.
    "$TMPDIR/first-plain-array"
    "$TMPDIR/second-plain-array"
    assertJson "$directory/plain-array.json" '. == ["a", "b"]'

    # Keys that mean something to jq or to the rules, and null leaves, are
    # removed like any other value; a null the application replaced is kept.
    reset
    "$TMPDIR/first-edge"
    edit "$directory/edge.json" '.nothing = 5'
    "$TMPDIR/second-edge"
    assertJson "$directory/edge.json" '. == {nothing: 5, kept: true}'

    # Records hold JSON for other formats too.
    "$TMPDIR/first-toml"
    assertRecord "$records/settings.toml.json" '{a: 1, b: 2}'
    "$TMPDIR/second-toml"
    assertFileContent "$directory/settings.toml" ${builtins.toFile "expected.toml" "a = 1\n"}
  '';
}
