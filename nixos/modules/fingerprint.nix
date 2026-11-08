_:

{
  # Standard libfprint readers only. The Apple Touch ID / secure-enclave
  # driver the original Arch setup used (libfprint-git + a custom
  # aurora-apple-sep.patch) lives in an external PKGBUILD not vendored in
  # this repo and has no nixpkgs equivalent -- that would need its own
  # overlay, authored separately, not guessed here.
  services.fprintd.enable = true;

  # The Inferna lock screen (core/shell/plugins/lock/Service.qml) refuses to
  # ever lock until /etc/pam.d/inferna-lock-password exists -- a deliberate
  # fail-safe ("no lock before PAM is known good") against engaging a lock
  # screen nothing can authenticate back out of. On Arch this file was
  # written at package-install time by core/bin/inferna-apply-lock (a pacman
  # post-install hook). NixOS has no equivalent install-time hook and /etc is
  # declarative anyway, so that script's `tee` would either no-op or get
  # overwritten on the next switch -- the file must be declared here instead.
  # Content matches inferna-apply-lock's password stack, with Arch's
  # system-local-login account substack replaced by a plain pam_unix check
  # (NixOS has no such substack to include).
  security.pam.services.inferna-lock-password.text = ''
    auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120
    -auth      [success=2 default=ignore]  pam_systemd_home.so
    auth       [success=1 default=bad]     pam_unix.so try_first_pass nullok
    auth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120
    auth       optional                    pam_permit.so
    auth       required                    pam_env.so
    auth       required                    pam_faillock.so authsucc
    account    required                    pam_unix.so
  '';
}
