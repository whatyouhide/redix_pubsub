defmodule Redix.PubSub do
  @moduledoc """
  Interface for the Redis PubSub functionality.

  The rest of this documentation will assume the reader knows how PubSub works
  in Redis and knows the meaning of the following Redis commands:

    * `SUBSCRIBE` and `UNSUBSCRIBE`
    * `PSUBSCRIBE` and `PUNSUBSCRIBE`
    * `PUBLISH`

  ## Usage

  Each `Redix.PubSub` process is able to subcribe to/unsubscribe from multiple
  Redis channels, and is able to handle multiple Elixir processes subscribing
  each to different channels.

  A `Redix.PubSub` process can be started via `Redix.PubSub.start_link/2`; such
  a process holds a single TCP connection to the Redis server.

  `Redix.PubSub` has a message-oriented API: all subscribe/unsubscribe
  operations are *fire-and-forget* operations (casts in `GenServer`-speak) that
  always return `:ok` to the caller, whether the operation has been processed by
  `Redix.PubSub` or not. When `Redix.PubSub` registers the
  subscription/unsubscription, it will send a confirmation message to the
  subscribed/unsubscribed process. For example:

      {:ok, pubsub} = Redix.PubSub.start_link()
      Redix.PubSub.subscribe(pubsub, "my_channel", self())
      #=> :ok
      receive do msg -> msg end
      #=> {:redix_pubsub, #PID<...>, :subscribed, %{to: "my_channel"}}

  After a subscription, messages published to a channel are delivered to all
  Elixir processes subscribed to that channel via `Redix.PubSub`:

      # Someone publishes "hello" on "my_channel"
      receive do msg -> msg end
      #=> {:redix_pubsub, #PID<...>, :message, %{channel: "my_channel", payload: "hello"}}

  ## Reconnections

  `Redix.PubSub` tries to be resilient to failures: when the connection with
  Redis is interrupted (for whatever reason), it will try to reconnect to the
  Redis server. When a disconnection happens, `Redix.PubSub` will notify all
  clients subscribed to all channels with a `{:redix_pubsub, pid, :disconnected,
  _}` message (more on the format of messages below). When the connection goes
  back up, `Redix.PubSub` takes care of actually re-subscribing to the
  appropriate channels on the Redis server and subscribers are notified with a
  `{:redix_pubsub, pid, :subscribed, _}` message, the same as when a client
  subscribes to a channel/pattern.

  ## Message format

  Most of the communication with a PubSub connection is done via (Elixir)
  messages: the subscribers of these messages will be the processes specified at
  subscription time (in `Redix.PubSub.subscribe/3` or `Redix.PubSub.psubscribe/3`).
  All `Redix.PubSub` messages have the same form: they're a four-element tuple
  that looks like this:

      {:redix_pubsub, pid, type, properties}

  where:

    * `pid` is the pid of the `Redix.PubSub` process that sent this message
    * `type` is the type of this message (e.g., `:subscribed` for subscription
      confirmations, `:message` for PubSub messages)
    * `properties` is a map of data related to that that varies based on `type`

  Given this format, it's easy to match on all Redix PubSub messages by just
  matching on `{:redix_pubsub, ^pid, _, _}`.

  #### List of possible message types and properties

  The following is a list of possible message types alongside the properties
  that each can have.

    * `:subscribe` or `:psubscribe` messages - they're sent as confirmation of
      subscription to a channel or pattern (respectively) (via
      `Redix.PubSub.subscribe/3` or `Redix.PubSub.psubscribe/3` or after a
      disconnection and reconnection). One `:subscribe`/`:psubscribe` message is
      received for every channel a process subscribed
      to. `:subscribe`/`:psubscribe` messages have the following properties:
        * `:to` - the channel/pattern the process has been subscribed to
    * `:unsubscribe` or `:punsubscribe` messages - they're sent as confirmation
      of unsubscription to a channel or pattern (respectively) (via
      `Redix.PubSub.unsubscribe/3` or `Redix.PubSub.punsubscribe/3`). One
      `:unsubscribe`/`:punsubscribe` message is received for every channel a
      process unsubscribes from. `:unsubscribe`/`:punsubscribe` messages have
      the following properties:
        * `:from` - the channel/pattern the process has unsubscribed from
    * `:message` messages - they're sent to subscribers to a given channel when
      a message is published on that channel. `:message` messages have the
      following properties:
        * `:channel` - the channel this message was published on
        * `:payload` - the contents of this message
    * `:pmessage` messages - they're sent to subscribers to a given pattern when
      a message is published on a channel that matches that pattern. `:pmessage`
      messages have the following properties:
        * `:channel` - the channel this message was published on
        * `:pattern` - the original pattern that matched the channel
        * `:payload` - the contents of this message
    * `:disconnected` messages - they're sent to all subscribers to all
      channels/patterns when the connection to Redis is interrupted.
      `:disconnected` messages have the following properties:
        * `:reason` - the reason for the disconnection (e.g., `:tcp_closed`)

  ## Examples

  This is an example of a workflow using the PubSub functionality; it uses
  [Redix](https://github.com/whatyouhide/redix) as a Redis client for publishing
  messages.

      {:ok, pubsub} = Redix.PubSub.start_link()
      {:ok, client} = Redix.start_link()

      Redix.PubSub.subscribe(pubsub, "my_channel", self())
      #=> :ok

      # We wait for the subscription confirmation
      receive do
        {:redix_pubsub, ^pubsub, :subscribed, %{to: "my_channel"}} -> :ok
      end

      Redix.command!(client, ~w(PUBLISH my_channel hello)

      receive do
        {:redix_pubsub, ^pubsub, :message, %{channel: "my_channel"} = properties} ->
          properties.payload
      end
      #=> "hello"

      Redix.PubSub.unsubscribe(pubsub, "foo", self())
      #=> :ok

      # We wait for the unsubscription confirmation
      receive do
        {:redix_pubsub, ^pubsub, :unsubscribed, _} -> :ok
      end

  """

  @type subscriber :: pid | port | atom | {atom, node}

  alias Redix.Utils

  @default_timeout 5_000

  @doc """
  Starts a PubSub connection to Redis.

  This function returns `{:ok, pid}` if the PubSub process is started successfully.

  The actual TCP connection to the Redis server may happen either synchronously,
  before `start_link/2` returns, or asynchronously: this behaviour is decided by
  the `:sync_connect` option (see below).

  This function accepts two arguments: the options to connect to the Redis
  server (like host, port, and so on) and the options to manage the connection
  and the resiliency. The Redis options can be specified as a keyword list or as
  a URI.

  ## Redis options

  ### URI

  In case `uri_or_redis_opts` is a Redis URI, it must be in the form:

      redis://[:password@]host[:port][/db]

  Here are some examples of valid URIs:

      redis://localhost
      redis://:secret@localhost:6397
      redis://example.com:6380/1

  Usernames before the password are ignored, so the these two URIs are
  equivalent:

      redis://:secret@localhost
      redis://myuser:secret@localhost

  The only mandatory thing when using URIs is the host. All other elements
  (password, port, database) are optional and their default value can be found
  in the "Options" section below.

  ### Options

  The following options can be used to specify the parameters used to connect to
  Redis (instead of a URI as described above):

    * `:host` - (string) the host where the Redis server is running. Defaults to
      `"localhost"`.
    * `:port` - (integer) the port on which the Redis server is
      running. Defaults to `6379`.
    * `:password` - (string) the password used to connect to Redis. Defaults to
      `nil`, meaning no password is used. When this option is provided, all Redix
      does is issue an `AUTH` command to Redis in order to authenticate.
    * `:database` - (integer or string) the database to connect to. Defaults to
      `nil`, meaning don't connect to any database (Redis connects to database
      `0` by default). When this option is provided, all Redix does is issue a
      `SELECT` command to Redis in order to select the given database.

  ## Connection options

  `connection_opts` is a list of options used to manage the connection. These
  are the Redix-specific options that can be used:

    * `:socket_opts` - (list of options) this option specifies a list of options
      that are passed to `:gen_tcp.connect/4` when connecting to the Redis
      server. Some socket options (like `:active` or `:binary`) will be
      overridden by `Redix.PubSub` so that it functions properly. Defaults to
      `[]`.
    * `:sync_connect` - (boolean) decides whether Redix should initiate the TCP
      connection to the Redis server *before* or *after* returning from
      `start_link/2`. This option also changes some reconnection semantics; read
      the ["Reconnections" page](http://hexdocs.pm/redix/reconnections.html) in
      the docs for `Redix` for more information.
    * `:backoff_initial` - (integer) the initial backoff time (in milliseconds),
      which is the time that will be waited by the `Redix.PubSub` process before
      attempting to reconnect to Redis after a disconnection or failed first
      connection. See the ["Reconnections"
      page](http://hexdocs.pm/redix/reconnections.html) in the docs for `Redix`
      for more information.
    * `:backoff_max` - (integer) the maximum length (in milliseconds) of the
      time interval used between reconnection attempts. See the ["Reconnections"
      page](http://hexdocs.pm/redix/reconnections.html) in the docs for `Redix`
      for more information.

  In addition to these options, all options accepted by
  `Connection.start_link/3` (and thus `GenServer.start_link/3`) are forwarded to
  it. For example, a `Redix.PubSub` process can be registered with a name by using the
  `:name` option:

      Redix.PubSub.start_link([], name: :redix_pubsub)
      Process.whereis(:redix_pubsub)
      #=> #PID<...>

  ## Examples

      iex> Redix.PubSub.start_link()
      {:ok, #PID<...>}

      iex> Redix.PubSub.start_link(host: "example.com", port: 9999, password: "secret")
      {:ok, #PID<...>}

      iex> Redix.PubSub.start_link([database: 3], [name: :redix_3])
      {:ok, #PID<...>}

  """
  @spec start_link(binary | Keyword.t, Keyword.t) :: GenServer.on_start
  def start_link(uri_or_redis_opts \\ [], connection_opts \\ [])

  def start_link(uri, other_opts) when is_binary(uri) and is_list(other_opts) do
    uri |> Redix.URI.opts_from_uri() |> start_link(other_opts)
  end

  def start_link(redis_opts, other_opts) do
    {redix_opts, connection_opts} = Utils.sanitize_starting_opts(redis_opts, other_opts)
    Connection.start_link(Redix.PubSub.Connection, redix_opts, connection_opts)
  end

  @doc """
  Stops the given PubSub process.

  This function is asynchronous (*fire and forget*): it returns `:ok` as soon as
  it's called and performs the closing of the connection after that.

  ## Examples

      iex> Redix.PubSub.stop(conn)
      :ok

  """
  @spec stop(GenServer.server) :: :ok
  def stop(conn) do
    Connection.cast(conn, :stop)
  end

  @doc """
  Subscribes `subscriber` to the given channel or list of channels.

  Subscribes `subscriber` (which can be anything that can be passed to `send/2`)
  to `channels`, which can be a single channel or a list of channels.

  For each of the channels in `channels` which `subscriber` successfully
  subscribes to, a message will be sent to `subscriber` with this form:

      {:redix_pubsub, pid, :subscribed, %{to: channel}}

  See the documentation for `Redix.PubSub` for more information about the format
  of messages.

  ## Examples

      iex> Redix.subscribe(conn, ["foo", "bar"], self())
      :ok
      iex> flush()
      {:redix_pubsub, #PID<...>, :subscribed, %{to: "foo"}}
      {:redix_pubsub, #PID<...>, :subscribed, %{to: "bar"}}
      :ok

  """
  @spec subscribe(GenServer.server, String.t | [String.t], subscriber) :: :ok
  def subscribe(conn, channels, subscriber) do
    Connection.cast(conn, {:subscribe, List.wrap(channels), subscriber})
  end

  @doc """
  Subscribes `subscriber` to the given pattern or list of patterns.

  Works like `subscribe/3` but subscribing `subscriber` to a pattern (or list of
  patterns) instead of regular channels.

  Upon successful subscription to each of the `patterns`, a message will be sent
  to `subscriber` with the following form:

      {:redix_pubsub, pid, :psubscribed, %{to: pattern}}

  See the documentation for `Redix.PubSub` for more information about the format
  of messages.

  ## Examples

      iex> Redix.psubscribe(conn, "ba*", self())
      :ok
      iex> flush()
      {:redix_pubsub, #PID<...>, :psubscribe, %{to: "ba*"}}
      :ok

  """
  @spec psubscribe(GenServer.server, String.t | [String.t], subscriber) :: :ok
  def psubscribe(conn, patterns, subscriber) do
    Connection.cast(conn, {:psubscribe, List.wrap(patterns), subscriber})
  end

  @doc """
  Unsubscribes `subscriber` from the given channel or list of channels.

  This function basically "undoes" what `subscribe/3` does: it unsubscribes
  `subscriber` from the given channel or list of channels.

  Upon successful unsubscription from each of the `channels`, a message will be
  sent to `subscriber` with the following form:

      {:redix_pubsub, pid, :unsubscribed, %{from: channel}}

  See the documentation for `Redix.PubSub` for more information about the format
  of messages.

  ## Examples

      iex> Redix.unsubscribe(conn, ["foo", "bar"], self())
      :ok
      iex> flush()
      {:redix_pubsub, #PID<...>, :unsubscribed, %{from: "foo"}}
      {:redix_pubsub, #PID<...>, :unsubscribed, %{from: "bar"}}
      :ok

  """
  @spec unsubscribe(GenServer.server, String.t | [String.t], subscriber) :: :ok
  def unsubscribe(conn, channels, subscriber) do
    Connection.cast(conn, {:unsubscribe, List.wrap(channels), subscriber})
  end

  @doc """
  Unsubscribes `subscriber` from the given pattern or list of patterns.

  This function basically "undoes" what `psubscribe/3` does: it unsubscribes
  `subscriber` from the given pattern or list of patterns.

  Upon successful unsubscription from each of the `patterns`, a message will be
  sent to `subscriber` with the following form:

      {:redix_pubsub, pid, :punsubscribed, %{to: pattern}}

  See the documentation for `Redix.PubSub` for more information about the format
  of messages.

  ## Examples

      iex> Redix.punsubscribe(conn, "foo_*", self())
      :ok
      iex> flush()
      {:redix_pubsub, #PID<...>, :punsubscribed, %{from: "foo_*"}}
      :ok

  """
  @spec punsubscribe(GenServer.server, String.t | [String.t], subscriber) :: :ok
  def punsubscribe(conn, patterns, subscriber) do
    Connection.cast(conn, {:punsubscribe, List.wrap(patterns), subscriber})
  end
end
