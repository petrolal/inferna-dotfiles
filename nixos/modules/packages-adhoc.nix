{ pkgs, ... }:

{
  # Managed programmatically by `inferna pkg add`/`inferna pkg remove` (see
  # core/bin/inferna-pkg-add, core/bin/inferna-pkg-drop). Hand-curated,
  # permanent packages belong in packages.nix instead -- this file is edited
  # by script, so it stays separate and minimal.
  environment.systemPackages = with pkgs; [
    # INFERNA_ADHOC_PACKAGES_START
    # INFERNA_ADHOC_PACKAGES_END
  ];
}
