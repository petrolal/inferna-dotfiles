{ config, lib, pkgs, ... }:

{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;

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
}
