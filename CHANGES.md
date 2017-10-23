## v5.1.0

- adding timeout as a contructor option

## v5.0.0

- `converse` and `run_actions` are deprecated
- `interactive` now calls `message`

### Breaking changes
- Renamed WitException to Wit::Error
- Changed Wit::Error to inherit from StandardError instead of Exception
- Moved constants inside Wit namespace
- Moved #req and #validate_actions to private methods within Wit namespace

## v4.1.0

- `converse` now takes `reset` as optional parameter.

### Breaking changes

- `run_actions` now resets the last turn on new messages and errors.

## v4.0.0

After a lot of internal dogfooding and bot building, we decided to change the API in a backwards-incompatible way. The changes are described below and aim to simplify user code and accommodate upcoming features.

See `./examples` to see how to use the new API.

### Breaking changes

- `say` renamed to `send` to reflect that it deals with more than just text
- Removed built-in actions `merge` and `error`
- Actions signature simplified with `request` and `response` arguments
- INFO level replaces LOG level

## v3.4

- allows for overriding API version, by setting `WIT_API_VERSION`
- `interactive()` mode
- warns instead of throwing when validating actions

### breaking

- bumped default API version from `20160330` to `20160516`

## v3.3.1

- fixed recursive call when running actions
- throws an exception if context passed is not a Hash

## v3.3

Unifying action parameters

### breaking

- the `say` action now takes 3 parameters: `session_id`, `context`, `msg`
- the `error` action now takes 3 parameters: `session_id`, `context`, `error`

## v3.2

Updating action parameters

### breaking

- the `merge` action now takes 4 parameters: `session_id`, `context`, `entities`, `msg`
- the `error` action now takes `context` as second parameter
- custom actions now take 2 parameters: `session_id`, `context`

## v3.1

- allows for custom logging
- better error message

## v3.0

Bot Engine integration

### breaking

- the `message` API is wrapped around a `Wit` class, and doesn't take the token as first parameter

## v2.0

Rewrite in pure Ruby

### breaking

- audio recording and streaming have been removed because:
  - many people only needed access to the HTTP API, and audio recording did not make sense for server-side use cases
  - dependent on platform, choice best left to developers
  - forced us to maintain native bindings as opposed to a pure Pythonic library
- we renamed the functions to match the HTTP API more closely
  - `.text_query(string, access_token)` becomes `.message(access_token, string)`
- all functions now return a Ruby dict instead of a JSON string
