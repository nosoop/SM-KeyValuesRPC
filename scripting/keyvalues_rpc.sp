/**
 * [ANY] KeyValues RPC
 * 
 * Exposes a TCP socket that receives calls that look similar to JSON-RPC.
 */

#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <newdecl-handles/socket>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[ANY] KeyValues RPC",
	author = "nosoop",
	description = "Remote procedure call server for SourceMod plugins.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-KeyValuesRPC"
};

#define MAX_RPC_METHOD_NAME_LENGTH 128

#define MAX_KV_RPC_RESPONSE_BUFFER_LENGTH 4096

enum eKVRPCError {
	KV_RPC_ERR_PARSE_ERROR = -32700,
	KV_RPC_ERR_METHOD_NOT_FOUND = -32601,
	KV_RPC_ERR_INVALID_REQUEST = -32600
}

StringMap g_RPCMethods; // <char[] identifier, Handle forward>
KeyValues g_CurrentRPCError;

Socket g_ServiceSocket;

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int err_max) {
	RegPluginLibrary("keyvalues-rpc");
	
	CreateNative("KeyValuesRPC_Register", Native_RegisterKeyValuesCall);
	CreateNative("ThrowKeyValuesRPCError", Native_ThrowKeyValuesCallError);
	return APLRes_Success;
}

char g_CurrentHost[PLATFORM_MAX_PATH];
int g_iCurrentPort;

ConVar g_ConVarBindHost, g_ConVarBindPort;

public void OnPluginStart() {
	g_RPCMethods = new StringMap();
	
	g_ConVarBindHost = CreateConVar("kv_rpc_bind_host", "127.0.0.1",
			"The hostname / IP address the KeyValues RPC server socket is bound to.");
	g_ConVarBindPort = CreateConVar("kv_rpc_bind_port", "27115",
			"The port the KeyValues RPC server socket is bound to.", _,
			true, 0.0, true, 65535.0);
	AutoExecConfig();
}

public void OnConfigsExecuted() {
	char host[128];
	g_ConVarBindHost.GetString(host, sizeof(host));
	
	if (!StrEqual(g_CurrentHost, host) || g_iCurrentPort != g_ConVarBindPort.IntValue) {
		RebindServer(host, g_ConVarBindPort.IntValue);
	}
}

static void RebindServer(const char[] host, int port) {
	if (g_ServiceSocket) {
		delete g_ServiceSocket;
	}
	g_ServiceSocket = new Socket(SOCKET_TCP, OnSocketError);
	
	// Bind it to loopback only for slightly more secure use
	if (g_ServiceSocket.Bind(host, port)) {
		PrintToServer("[keyvalues-rpc] Server is bound to %s:%d", host, port);
		g_ServiceSocket.Listen(OnSocketIncoming);
		
		strcopy(g_CurrentHost, sizeof(g_CurrentHost), host);
		g_iCurrentPort = port;
	} else {
		PrintToServer("[keyvalues-rpc] Server failed to bind to %s:%d", host, port);
	}
}

/* Sockets */

public int OnSocketIncoming(Socket socket, Socket childSocket, char[] ip, int port, any data) {
	childSocket.ReceiveCallback = OnChildSocketReceive;
	childSocket.DisconnectCallback = OnChildSocketDisconnected;
	childSocket.ErrorCallback = OnSocketError;
}

public int OnChildSocketReceive(Socket socket, char[] request, int requestSize, any data) {
	KeyValues requestKV = new KeyValues("keyvalues_rpc");
	KeyValues responseKV = new KeyValues("keyvalues_rpc", "rpc_version", "2.0");
	
	// fail fast
	if (!requestKV.ImportFromString(request)) {
		responseKV.SetNum("error/code", KV_RPC_ERR_PARSE_ERROR);
		responseKV.SetString("error/message", "Parse error");
		responseKV.SetString("id", "");
		
		WriteKeyValuesToSocket(socket, responseKV);
		
		delete requestKV;
		delete responseKV;
		delete socket;
		
		return;
	}
	
	char id[128];
	requestKV.GetString("id", id, sizeof(id));
	responseKV.SetString("id", id);
	
	char method[MAX_RPC_METHOD_NAME_LENGTH];
	requestKV.GetString("method", method, sizeof(method));
	
	if (!method[0]) {
		// no method name supplied
		responseKV.SetNum("error/code", KV_RPC_ERR_INVALID_REQUEST);
		responseKV.SetString("error/message", "Invalid request (no method name)");
	} else {
		Handle hForward;
		if (!GetRegisteredKeyValuesCall(method, hForward)) {
			// method name not registered
			responseKV.SetNum("error/code", KV_RPC_ERR_METHOD_NOT_FOUND);
			
			char message[128];
			Format(message, sizeof(message), "Method '%s' not found", method);
			
			responseKV.SetString("error/message", message);
			responseKV.SetString("id", id);
		} else {
			// method registered, call it
			
			// get parameter info from request string, if any
			KeyValues methodParamsKV = new KeyValues("params");
			if (requestKV.JumpToKey("params")) {
				methodParamsKV.Import(requestKV);
			}
			
			int error;
			KeyValues methodResponseKV = new KeyValues("response");
			
			Call_StartForward(hForward);
			Call_PushCell(methodParamsKV);
			Call_PushCell(methodResponseKV);
			Call_Finish(error);
			delete methodParamsKV;
			
			if (!g_CurrentRPCError && !error) {
				if (responseKV.JumpToKey("result", true)) {
					responseKV.Import(methodResponseKV);
					responseKV.GoBack();
				}
			} else {
				if (!g_CurrentRPCError) {
					SetCurrentKeyValuesRPCError(error,
							"Method returned with non-zero return value %d", error);
				}
				if (responseKV.JumpToKey("error", true)) {
					responseKV.Import(g_CurrentRPCError);
					responseKV.GoBack();
				}
				// populate error object
				delete g_CurrentRPCError;
			}
			
			delete methodResponseKV;
		}
	}
	
	if (id[0]) {
		WriteKeyValuesToSocket(socket, responseKV);
	}
	
	delete requestKV;
	delete responseKV;
	
	delete socket;
}

public int OnChildSocketDisconnected(Socket socket, any data) {
	delete socket;
}

public int OnSocketError(Socket socket, const int errorType, const int errorNum, any data) {
	delete socket;
}

/* native void KeyValuesRPC_Register(const char[] name, KeyValuesRPCFunction func); */
public int Native_RegisterKeyValuesCall(Handle plugin, int nParams) {
	char method[MAX_RPC_METHOD_NAME_LENGTH];
	GetNativeString(1, method, sizeof(method));
	
	if (GetRegisteredKeyValuesCall(method)) {
		return ThrowNativeError(1, "%s is already a registered function.", method);
	}
	
	Function func = GetNativeFunction(2);
	
	Handle hForward = CreateForward(ET_Single, Param_Cell, Param_Cell);
	AddToForward(hForward, plugin, func);
	
	g_RPCMethods.SetValue(method, hForward);
	return true;
}

/* native any ThrowKeyValuesRPCError(int error, const char[] fmt, any...); */
public int Native_ThrowKeyValuesCallError(Handle plugin, int nParams) {
	if (g_CurrentRPCError) {
		delete g_CurrentRPCError;
	}
	
	int code = GetNativeCell(1);
	
	char message[1024];
	FormatNativeString(0, 2, 3, sizeof(message), .out_string = message);
	
	SetCurrentKeyValuesRPCError(code, message);
	return code;
}

/**
 * Sets the current KeyValues RPC's error.
 */
static void SetCurrentKeyValuesRPCError(int code, const char[] fmt, any ...) {
	if (g_CurrentRPCError) {
		delete g_CurrentRPCError;
	}
	
	char message[1024];
	VFormat(message, sizeof(message), fmt, 3);
	
	g_CurrentRPCError = new KeyValues("error");
	g_CurrentRPCError.SetNum("code", code);
	g_CurrentRPCError.SetString("message", message);
}

/**
 * Writes a KeyValues string to a socket.
 */
void WriteKeyValuesToSocket(Socket socket, KeyValues kv) {
	char responseBuffer[MAX_KV_RPC_RESPONSE_BUFFER_LENGTH];
	kv.ExportToString(responseBuffer, sizeof(responseBuffer));
	
	socket.Send(responseBuffer);
}

/**
 * Returns true if a KeyValues call with the specified name exists, storing the private forward
 * handle in `hForward`.
 */
static bool GetRegisteredKeyValuesCall(const char[] name, Handle &hForward = INVALID_HANDLE) {
	if (!g_RPCMethods.GetValue(name, hForward)) {
		return false;
	}
	if (!GetForwardFunctionCount(hForward)) {
		g_RPCMethods.Remove(name);
		return false;
	}
	return true;
}
