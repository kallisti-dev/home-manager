{
  mutable-settings-legacy-state-version = import ./state-version.nix {
    stateVersion = "26.05";
    removed = false;
  };
  mutable-settings-state-version = import ./state-version.nix {
    stateVersion = "26.11";
    removed = true;
  };
}
