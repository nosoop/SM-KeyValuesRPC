/**
 * KeyValues RPC Example
 * Provides the KeyValues RPC server with a few functions.
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required
#include <keyvalues_rpc>

public void OnPluginStart() {
	KeyValuesRPC_Register("engine_time", ServeEngineTime);
	KeyValuesRPC_Register("give_me_a_failure", ServeError);
	KeyValuesRPC_Register("add_my_numbers", ServerAdd);
	KeyValuesRPC_Register("echo", ServerEcho);
}

public int ServeEngineTime(KeyValues params, KeyValues response) {
	response.SetFloat("time", GetEngineTime());
}

public int ServeError(KeyValues params, KeyValues response) {
	response.SetString("should_be_visible", "false");
	return ThrowKeyValuesRPCError(1, "You get an error!");
}

public int ServerAdd(KeyValues params, KeyValues response) {
	response.SetNum("sum", params.GetNum("a") + params.GetNum("b"));
}

public int ServerEcho(KeyValues params, KeyValues response) {
	char message[256];
	params.GetString("message", message, sizeof(message));
	response.SetString("message", message);
}
