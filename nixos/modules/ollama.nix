{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dotfiles.ollama;
  resolvedAcceleration =
    if cfg.acceleration != "auto" then
      cfg.acceleration
    else if config.dotfiles.nvidia.enable then
      "cuda"
    else if config.dotfiles.gpu.vendor == "amd" then
      "rocm"
    else
      "cpu";

  ollamaPackage =
    if resolvedAcceleration == "cuda" then
      pkgs.ollama-cuda
    else if resolvedAcceleration == "rocm" then
      pkgs.ollama-rocm
    else
      pkgs.ollama;
in
{
  options.dotfiles.ollama = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install on-demand Ollama local LLM service.";
    };

    acceleration = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "cuda"
        "rocm"
        "cpu"
      ];
      default = "auto";
      description = "Hardware acceleration backend for Ollama (auto picks cuda for NVIDIA, rocm for AMD, cpu otherwise).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = ollamaPackage;

      # Models to pull when ollama-model-loader is started manually
      # (see https://ollama.com/library).
      loadModels = [
        "llama3.2"
        "nomic-embed-text"
      ];
    };

    # Keep Ollama on-demand instead of running CUDA/daemon from boot.
    # Start when needed with: sudo systemctl start ollama
    systemd.services.ollama.wantedBy = lib.mkForce [ ];
    systemd.services.ollama-model-loader.wantedBy = lib.mkForce [ ];
  };
}
