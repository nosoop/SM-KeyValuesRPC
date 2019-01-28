/**
 * KeyValues RPC
 * Expose plugin functions over a JSON-RPC-like protocol over TCP.
 */

#if defined __keyvalues_rpc_included
	#endinput
#endif

#define __keyvalues_rpc_included

/** 
 * Defines a KeyValues RPC function.
 * 
 * @param params		A valid KeyValues handle containing parameters.  The KeyValues struct
 * 						may be empty if no parameters are passed in.
 * @param response		A valid KeyValues handle to be populated with a response.  This may be
 * 						discarded if the RPC call is a notification.
 * 
 * @return				0 on success, any other integer on failure.
 */
typedef KeyValuesRPCFunction = function int(KeyValues params, KeyValues response);

/**
 * Registers a KeyValues RPC function.
 */
native void KeyValuesRPC_Register(const char[] name, KeyValuesRPCFunction func);

/**
 * Populates the error field of the current KeyValues RPC response.
 * Convention is to `return ThrowKeyValuesRPCError(...)` if a KeyValuesRPCFunction wants to
 * report an error.
 * 
 * @return				The input error code.
 */
native any ThrowKeyValuesRPCError(int error, const char[] fmt, any...);

public SharedPlugin __pl_keyvalues_rpc = {
	name = "keyvalues-rpc",
	file = "keyvalues_rpc",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_keyvalues_rpc_SetNTVOptional() {
	MarkNativeAsOptional("KeyValuesRPC_Register");
	MarkNativeAsOptional("ThrowKeyValuesRPCError");
}
#endif
