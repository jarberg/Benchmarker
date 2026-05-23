# Seed presets so the UI has something to show on a fresh DB.
alias Benchmarker.Benchmarks

presets = [
  %{
    name: "Generic 60s 1080p",
    config: %{exeConfig: "generic", duration_seconds: 60, executable: "bin/game.exe"}
  },
  %{
    name: "UE5 High 1080p",
    config: %{exeConfig: "unreal", duration_seconds: 90, executable: "Binaries/Win64/MyGame.exe"}
  },
  %{
    name: "Unity 60s 1080p",
    config: %{exeConfig: "unity", duration_seconds: 60, executable: "Builds/Game.exe"}
  }
]

Enum.each(presets, fn attrs ->
  Benchmarks.create_config!(attrs)
end)
