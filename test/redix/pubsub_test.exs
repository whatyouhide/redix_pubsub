defmodule Redix.PubSubTest do
  use ExUnit.Case

  import Redix.TestHelpers
  alias Redix.PubSub

  setup do
    {:ok, ps} = PubSub.start_link
    on_exit(fn -> PubSub.stop(ps) end)
    {:ok, %{conn: ps}}
  end

  test "subscribe/unsubscribe flow", %{conn: ps} do
    {:ok, c} = Redix.start_link()

    # First, we subscribe.
    assert :ok = PubSub.subscribe(ps, ["foo", "bar"], self())
    assert_receive {:redix_pubsub, ^ps, :subscribed, %{channel: "foo"}}
    assert_receive {:redix_pubsub, ^ps, :subscribed, %{channel: "bar"}}

    # Then, we test messages are routed correctly.
    Redix.command!(c, ~w(PUBLISH foo hello))
    assert_receive {:redix_pubsub, ^ps, :message, %{channel: "foo", payload: "hello"}}
    Redix.command!(c, ~w(PUBLISH bar world))
    assert_receive {:redix_pubsub, ^ps, :message, %{channel: "bar", payload: "world"}}

    # Then, we unsubscribe.
    assert :ok = PubSub.unsubscribe(ps, ["foo"], self())
    assert_receive {:redix_pubsub, ^ps, :unsubscribed, %{channel: "foo"}}

    # And finally, we test that we don't receive messages anymore for
    # unsubscribed channels, but we do for subscribed channels.
    Redix.command!(c, ~w(PUBLISH foo hello))
    refute_receive {:redix_pubsub, ^ps, :message, %{channel: "foo", payload: "hello"}}
    Redix.command!(c, ~w(PUBLISH bar world))
    assert_receive {:redix_pubsub, ^ps, :message, %{channel: "bar", payload: "world"}}
  end

  test "psubscribe/punsubscribe flow", %{conn: ps} do
    {:ok, c} = Redix.start_link

    PubSub.psubscribe(ps, ["foo*", "ba?"], self())
    assert_receive {:redix_pubsub, ^ps, :psubscribed, %{pattern: "foo*"}}
    assert_receive {:redix_pubsub, ^ps, :psubscribed, %{pattern: "ba?"}}

    Redix.pipeline!(c, [
      ~w(PUBLISH foo_1 foo_1),
      ~w(PUBLISH foo_2 foo_2),
      ~w(PUBLISH bar bar),
      ~w(PUBLISH barfoo barfoo),
    ])

    assert_receive {:redix_pubsub, ^ps, :pmessage, %{payload: "foo_1", channel: "foo_1", pattern: "foo*"}}
    assert_receive {:redix_pubsub, ^ps, :pmessage, %{payload: "foo_2", channel: "foo_2", pattern: "foo*"}}
    assert_receive {:redix_pubsub, ^ps, :pmessage, %{payload: "bar", channel: "bar", pattern: "ba?"}}
    refute_receive {:redix_pubsub, ^ps, :pmessage, %{payload: "barfoo"}}

    PubSub.punsubscribe(ps, "foo*", self())
    assert_receive {:redix_pubsub, ^ps, :punsubscribed, %{pattern: "foo*"}}

    Redix.pipeline!(c, [~w(PUBLISH foo_x foo_x), ~w(PUBLISH baz baz)])

    refute_receive {:redix_pubsub, ^ps, :pmessage, %{payload: "foo_x"}}
    assert_receive {:redix_pubsub, ^ps, :pmessage, %{payload: "baz", channel: "baz", pattern: "ba?"}}
  end

  test "subscribing the same pid to the same channel more than once has no effect", %{conn: ps} do
    {:ok, c} = Redix.start_link

    assert :ok = PubSub.subscribe(ps, "foo", self())
    assert :ok = PubSub.subscribe(ps, "foo", self())
    assert_receive {:redix_pubsub, ^ps, :subscribed, %{channel: "foo"}}
    assert_receive {:redix_pubsub, ^ps, :subscribed, %{channel: "foo"}}

    Redix.command!(c, ~w(PUBLISH foo hello))

    assert_receive {:redix_pubsub, ^ps, :message, %{channel: "foo", payload: "hello"}}
    refute_receive {:redix_pubsub, ^ps, :message, %{channel: "foo", payload: "hello"}}
  end

  test "pubsub: unsubscribing a recipient doesn't affect other recipients", %{conn: ps} do
    {:ok, c} = Redix.start_link

    parent = self()
    mirror = spawn_link(fn -> message_mirror(parent) end)

    # Let's subscribe two different pids to the same channel.
    assert :ok = PubSub.subscribe(ps, ["foo"], self())
    assert_receive {:redix_pubsub, ^ps, :subscribed, _properties}
    assert :ok = PubSub.subscribe(ps, ["foo"], mirror)
    assert_receive {^mirror, {:redix_pubsub, ^ps, :subscribed, _properties}}

    # Let's ensure both those pids receive messages published on that channel.
    Redix.command!(c, ~w(PUBLISH foo hello))
    assert_receive {:redix_pubsub, ^ps, :message, %{payload: "hello"}}
    assert_receive {^mirror, {:redix_pubsub, ^ps, :message, %{payload: "hello"}}}

    # Now let's unsubscribe just one pid from that channel.
    PubSub.unsubscribe(ps, "foo", self())
    assert_receive {:redix_pubsub, ^ps, :unsubscribed, %{channel: "foo"}}
    refute_receive {^mirror, {:redix_pubsub, ^ps, :unsubscribed, %{channel: "foo"}}}

    # Publishing now should send a message to the non-unsubscribed pid.
    Redix.command!(c, ~w(PUBLISH foo hello))
    refute_receive {:redix_pubsub, ^ps, :message, %{payload: "hello"}}
    assert_receive {^mirror, {:redix_pubsub, ^ps, :message, %{payload: "hello"}}}
  end

  test "recipients are monitored and the connection unsubcribes when they go down", %{conn: ps} do
    parent = self()
    pid = spawn(fn -> message_mirror(parent) end)

    assert :ok = PubSub.subscribe(ps, "foo", pid)
    assert_receive {^pid, {:redix_pubsub, ^ps, :subscribed, %{channel: "foo"}}}

    # Let's just ensure no errors happen when we kill the recipient.
    Process.exit(pid, :kill)

    :timer.sleep(100)
  end

  test "disconnections/reconnections", %{conn: ps} do
    assert :ok = PubSub.subscribe(ps, "foo", self())
    assert_receive {:redix_pubsub, ^ps, :subscribed, %{channel: "foo"}}

    {:ok, c} = Redix.start_link

    silence_log fn ->
      Redix.command!(c, ~w(CLIENT KILL TYPE pubsub))
      assert_receive {:redix_pubsub, ^ps, :disconnected, %{reason: _reason}}
      assert_receive {:redix_pubsub, ^ps, :subscribed, %{channel: "foo"}}, 1000
    end

    Redix.command!(c, ~w(PUBLISH foo hello))
    assert_receive {:redix_pubsub, ^ps, :message, %{channel: "foo", payload: "hello"}}
  end

  test ":exit_on_disconnection option" do
    {:ok, ps} = PubSub.start_link([], exit_on_disconnection: true)
    {:ok, c} = Redix.start_link

    # We need to subscribe to something so that this client becomes a PubSub
    # client and we can kill it with "CLIENT KILL TYPE pubsub".
    assert :ok = PubSub.subscribe(ps, "foo", self())
    assert_receive {:redix_pubsub, ^ps, :subscribed, %{channel: "foo"}}

    Process.flag(:trap_exit, true)

    silence_log fn ->
      Redix.command!(c, ~w(CLIENT KILL TYPE pubsub))
      assert_receive {:EXIT, ^ps, :tcp_closed}
    end
  end

  # This function just sends back to this process every message it receives.
  defp message_mirror(parent) do
    receive do
      msg -> send(parent, {self(), msg})
    end
    message_mirror(parent)
  end
end
