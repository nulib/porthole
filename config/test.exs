use Mix.Config

config :logger, :console,
  format: "[$level] $levelpad$message\n",
  colors: [enabled: false]
