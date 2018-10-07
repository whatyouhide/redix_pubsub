# Redix PubSub

[![Build Status](https://travis-ci.org/whatyouhide/redix_pubsub.svg?branch=master)](https://travis-ci.org/whatyouhide/redix_pubsub)

> Elixir library for Redis Pub/Sub (based on [Redix][redix]).

For basic Redis-related functionality, use [Redix][redix].

## Installation

Add the `:redix_pubsub` dependency to your `mix.exs` file:

```elixir
defp deps() do
  [{:redix_pubsub, ">= 0.0.0"}]
end
```

Use `mix hex.info redix_pubsub` to find out what the latest version is. Then, run `mix deps.get` in your shell to fetch the new dependency. Note that this library requires Erlang 20+.

## Usage

A `Redix.PubSub` process holds a connection to Redis and acts as a pub/sub intermediary between the Redis server and Elixir processes. The architecture looks like this:

![Redix.PubSub architecture](https://i.imgur.com/Ev9sSK0.png)

Each `Redix.PubSub` process is able to subcribe to or unsubscribe from multiple Redis channels. One `Redix.PubSub` connection can handle multiple Elixir processes subscribing each to different channels.

A `Redix.PubSub` process can be started via `Redix.PubSub.start_link/2`:

```elixir
{:ok, pubsub} = Redix.PubSub.start_link()
```

Most communication with the `Redix.PubSub` process happens via Elixir messages (that simulate a Pub/Sub interaction with the pub/sub server).

```elixir
{:ok, pubsub} = Redix.PubSub.start_link()

Redix.PubSub.subscribe(pubsub, "my_channel", self())
#=> {:ok, ref}
```

Confirmation of subscriptions is delivered as an Elixir message:

```elixir
receive do
  {:redix_pubsub, ^pubsub, ^ref, :subscribed, %{channel: "my_channel"}} -> :ok
end
```

If someone publishes a message on a channel we're subscribed to:

```elixir
receive do
  {:redix_pubsub, ^pubsub, ^ref, :message, %{channel: "my_channel", payload: "hello"}} ->
    IO.puts("Received a message!")
end
```

More information on usage of this library can be found in the [documentation][docs].

## License

ISC 2016, Andrea Leopardi (see [LICENSE.txt](LICENSE.txt))

[docs]: http://hexdocs.pm/redix_pubsub
[redix]: https://github.com/whatyouhide/redix
