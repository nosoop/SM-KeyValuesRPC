# KeyValues RPC Server

A plugin that allows other plugins to expose functions via a custom remote procedure call (RPC)
protocol over TCP.  Requires [the Socket extension].

[the Socket extension]: https://forums.alliedmods.net/showthread.php?t=67640

I currently have a dedicated plugin whose only purpose is to listen to a socket and serve one
hard-coded function; figured it was about time to split it to a socket listener / call dispatch
and a plugin that registers itself as a call handler.

The payload specification is based off of JSON-RPC 2.0, with a few modifications:

* The payload is a string in KeyValues format.  The section name must be `keyvalues_rpc`, and
there must be an `rpc_version` key with the value "2.0".
* The `params` and `result` keys, if they are present, indicate subsections (that is, they are
not basic values).
* There is no support for batching requests.
