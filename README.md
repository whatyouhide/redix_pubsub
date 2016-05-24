# Redix PubSub

> Elixir library for Redis Pub/Sub (based on [Redix][redix])

## Installation

Add the `:redix_pubsub` dependency to your `mix.exs` file:

```elixir
defp deps() do
  [{:redix_pubsub, ">= 0.0.0"}]
end
```

and add `:redix_pubsub` to your list of applications:

```elixir
defp application() do
  [applications: [:logger, :redix_pubsub]]
end
```

Then, run `mix deps.get` in your shell to fetch the new dependency.

## Usage

Each `Redix.PubSub` process is able to subcribe to/unsubscribe from multiple
Redis channels, and is able to handle multiple Elixir processes subscribing each
to different channels.

A `Redix.PubSub` process can be started via `Redix.PubSub.start_link/2`:

```elixir
{:ok, pubsub} = Redix.PubSub.start_link()
```

This process will hold a single TCP connection to Redis. All other communication
happens via Elixir messages (that simulate a Pub/Sub interaction with the
`Redix.PubSub` process). Subscribing (to channels and patterns) as well as
unsubscribing work as *fire-and-forget* operations (casts in `GenServer`-speak)
that always return `:ok`: the subscription/unsubscription confirmation comes as
an Elixir message.

```elixir
{:ok, pubsub} = Redix.PubSub.start_link()

Redix.PubSub.subscribe(pubsub, "my_channel", self())
#=> :ok

# Now, messages will be sent to the current process. Let's wait for the
# subscription confirmation:
receive do
  {:redix_pubsub, ^pubsub, :subscribed, %{to: "my_channel"}} -> :ok
end

# Now, someone publishes "hello" on "my_channel":
receive do
  {:redix_pubsub, ^pubsub, :message, %{channel: "my_channel", payload: "hello"}} ->
    IO.puts "Received a message!"
end
```

More information on usage of this library can be found in the [documentation][docs].

## License

ISC 2016, Andrea Leopardi (see [LICENSE.txt](LICENSE.txt))


[docs]: http://hexdocs.pm/redix_pubsub
[redix]: https://github.com/whatyouhide/redix
