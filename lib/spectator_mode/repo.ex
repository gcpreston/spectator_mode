defmodule SpectatorMode.Repo do
  use Ecto.Repo,
    otp_app: :spectator_mode,
    adapter: Ecto.Adapters.Postgres
end
