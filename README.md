# SpectatorMode

<img width="1274" alt="Screenshot 2025-04-22 at 11 33 12 AM" src="https://github.com/user-attachments/assets/14877f38-d7bc-47d9-bb5d-947626f6b3b3" />

Stream and spectate SSBM games directly in the browser! This project is currently deployed at https://spectator-mode.fly.dev. The command line client can be found at https://github.com/gcpreston/swb.

## Usage

To use SpectatorMode, you must run the client locally, which forwards Slippi data to the web server. To do so:

- Download and install [NodeJS](https://nodejs.org/en/download)
- Open Slippi Dolphin
- In the terminal, run `npx @gcpreston/swb start`
  * If you'll be repeatedly streaming, install the client with `npm install -g @gcpreston/swb`, and then run it each time with `swb start`

## Local development

The web server is built with Phoenix. To start the server locally:
- Run `mix setup` to install and setup dependencies
- Start the endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser. More information can be found in the [Phoenix installation and setup guide](https://hexdocs.pm/phoenix/installation.html).

Instructions to run the client locally and connect to the local web server can be found in the [swb repository](https://github.com/gcpreston/swb).

## Acknowledgements

This project is only possible thanks to
- [frankborden](https://github.com/frankborden) for [Slippi Lab](https://github.com/frankborden/slippilab)
- [Fizzi](https://github.com/JLaferri) and [the whole Slippi team](https://github.com/project-slippi) for [Project Slippi](https://slippi.gg)
