ExUnit.configure(assert_receive_timeout: 500, refute_receive_timeout: 500)
ExUnit.start()

case :gen_tcp.connect('localhost', 6379, []) do
  {:ok, socket} ->
    :gen_tcp.close(socket)
  {:error, reason} ->
    Mix.raise "Cannot connect to Redis (http://localhost:6379): #{:inet.format_error(reason)}"
end
