defmodule SpectatorMode.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SpectatorModeWeb.Telemetry,
      SpectatorMode.Repo,
      {DNSCluster, query: Application.get_env(:spectator_mode, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SpectatorMode.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: SpectatorMode.Finch},
      # Start a worker by calling: SpectatorMode.Worker.start_link(arg)
      # {SpectatorMode.Worker, arg},
      {Registry, name: SpectatorMode.BridgeRegistry, keys: :unique},
      {DynamicSupervisor, name: SpectatorMode.RelaySupervisor, strategy: :one_for_one},
      {SpectatorMode.ReconnectTokenStore, name: {:global, SpectatorMode.ReconnectTokenStore}},
      # Start to serve requests, typically the last entry
      SpectatorModeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SpectatorMode.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SpectatorModeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
