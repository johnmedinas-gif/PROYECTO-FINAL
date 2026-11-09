import Config

config :emergencias, data_dir: "data"

if config_env() == :test do
  config :emergencias, data_dir: "tmp/test_data"
end
