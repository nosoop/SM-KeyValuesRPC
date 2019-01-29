#!/usr/bin/python3

# This is a KeyValues RPC client implementation in Python 3.

import vdf
import socket

RPC_CONNECTION = ('127.0.0.1', 27115)

class KVRPCException(Exception):
	pass

def keyvalues_rpc_call(method: str, **kwargs):
	'''
	Performs a KeyValues RPC call.
	'''
	with socket.create_connection(RPC_CONNECTION) as caller:
		call_dict = {
			"rpc_version": "2.0",
			"method": method,
			"id": "string_identifier",
			"params": kwargs
		}
		caller.send(vdf.dumps({ 'keyvalues_rpc': call_dict }).encode('utf8'))
		response = vdf.loads(caller.recv(4096).decode('utf8')).get('keyvalues_rpc')
		
		error = response.get('error')
		if error:
			raise KVRPCException({
				'message': error.get('message'),
				'code': error.get('code')
			})
		
		result = response.get('result')
		return dict(result) if result else None

def keyvalues_rpc_notification(method: str, **kwargs):
	'''
	Performs a KeyValues RPC call.
	'''
	with socket.create_connection(RPC_CONNECTION) as caller:
		call_dict = {
			"rpc_version": "2.0",
			"method": method,
			"params": kwargs
		}
		caller.send(vdf.dumps({ 'keyvalues_rpc': call_dict }).encode('utf8'))

print(*[
	keyvalues_rpc_call('engine_time'),
	keyvalues_rpc_call('give_me_a_failure'),
	keyvalues_rpc_call('add_my_numbers', a = 1, b = 178),
	keyvalues_rpc_call('not_a_valid_function'),
	keyvalues_rpc_call('echo', message = "お嬢様、足の匂いをいただけませんか？"),
], sep  = '\n')
