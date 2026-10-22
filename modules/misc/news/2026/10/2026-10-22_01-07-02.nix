{ config, lib, ... }:
let
  inherit (config) programs services;
  mutable = cfg: cfg.enable && cfg.mutableSettings;
  inherit (programs) t3code vesktop zed-editor;
  colimaProfiles = lib.attrValues services.colima.profiles;
in
{
  time = "2026-10-22T01:07:02+00:00";
  condition = lib.any lib.id [
    (lib.any mutable [
      programs.algia
      programs.alistral
      programs.andcli
      programs.antigravity-cli
      programs.claude-code
      programs.codex
      programs.cudatext
      programs.github-copilot-cli
      programs.herdr
      services.plex-mpv-shim
    ])
    (
      t3code.enable
      && (t3code.mutableUserSettings || t3code.mutableKeybindings || t3code.mutableClientSettings)
    )
    (vesktop.enable && (vesktop.mutableSettings || vesktop.vencord.mutableSettings))
    (
      zed-editor.enable
      && (
        zed-editor.mutableUserSettings
        || zed-editor.mutableUserKeymaps
        || zed-editor.mutableUserTasks
        || zed-editor.mutableUserDebug
      )
    )
    (services.colima.enable && lib.any (profile: profile.mutableSettings) colimaProfiles)
    (programs.github-copilot-cli.enable && programs.github-copilot-cli.trustedFolders != [ ])
    # These modules always merge their settings.
    programs.joplin-desktop.enable
    programs.readest.enable
    services.jellyfin-mpv-shim.enable
  ];
  message = ''
    Home Manager can now remove a setting from a writable configuration file
    when you remove its declaration. This applies wherever declared settings
    are merged into a file that the application can also change, such as
    with `programs.claude-code.mutableSettings`,
    `programs.codex.mutableSettings`, or
    `programs.zed-editor.mutableUserSettings`, and for Joplin, Readest, and
    Jellyfin MPV Shim, which always merge their settings.

    Removal is controlled by `home.mutableSettings.removeDropped`, which is
    enabled by default when `home.stateVersion` is "26.11" or later. With an
    earlier state version nothing is removed unless you set it to `true`.

    Home Manager records the settings it merged under
    `~/.local/state/home-manager/mutable-settings`, or under
    `$XDG_STATE_HOME` when it is set, also while removal is disabled. With
    removal enabled, a recorded setting that is no longer declared is removed
    at the next activation unless the application has changed it since.
    Settings the application added itself are kept, and some modules remove
    or keep entries as a whole so that the application can still read the
    file. Settings removed while removal was disabled stay in the file;
    remove those by hand.
  '';
}
