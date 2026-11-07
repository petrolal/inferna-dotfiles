_:

{
  # Standard libfprint readers only. The Apple Touch ID / secure-enclave
  # driver the original Arch setup used (libfprint-git + a custom
  # aurora-apple-sep.patch) lives in an external PKGBUILD not vendored in
  # this repo and has no nixpkgs equivalent -- that would need its own
  # overlay, authored separately, not guessed here.
  services.fprintd.enable = true;
}
