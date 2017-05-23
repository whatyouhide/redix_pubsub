# Changelog

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
