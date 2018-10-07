# Changelog

## v0.5.0

### Breaking changes

- Bump the Elixir version to ~> 1.6.
- Bump the Redix version to ~> 0.8.
- Require Erlang/OTP 20+.
- Change message format to always include a subscription reference (returned by `Redix.PubSub.subscribe/3` or `Redix.PubSub.psubscribe/3`) as the third element. The format is now `{:redix_pubsub, pubsub_pid, subscription_ref, message_type, message_properties}`. Change your code accordingly or it won't
match on pub/sub messages anymore. See the documentation for `Redix.PubSub` for detailed information on the message format.
- Change the return value of `Redix.PubSub.subscribe/3` and `Redix.PubSub.psubscribe/3` to be `{:ok, subscription_ref}`.
- Make all subscribe/unsubscribe functions blocking until the pub/sub connection can process them.

### Bug fixes and improvements

- Add support for SSL through the `ssl: true | false` option in `Redix.PubSub.start_link/0,1,2`.
- Use `:gen_statem` in order to drop the dependency on [Connection](https://github.com/fishcakez/connection).

## v0.4.2

- Fix some deprecation warnings.

## v0.4.1

- Fix a bug related to connection errors.

## v0.4.0

- Bump the Redix dependency to ~> v0.6.0, which changed connection errors from being any term to being `Redix.ConnectionError` exception structs.
- Send `%{error: %Redix.ConnectionError{}}` metadata in the `:disconnected` message.

## v0.3.0

- Bump the Redix dependency to ~> v0.5.2, which fixed some bugs.

## v0.2.0

- Bump the Elixir requirement to ~> 1.2.

## v0.1.1

- Fixed a bug that happened when unsubscribing more than once.

## v0.1.0

- First release.
