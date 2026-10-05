#!/usr/bin/env python3
"""Return temporary items through the Bend actor, then acknowledge durable save."""
import json, os, socket, sys, time


def transaction():
    deadline = time.monotonic() + 8
    private = None
    try:
        while True:
            private = socket.create_connection(('127.0.0.1', int(os.environ['MC_RENDER_PORT'])), timeout=5)
            reader = private.makefile('rb')

            def exchange(value):
                private.sendall((json.dumps(value, ensure_ascii=True, separators=(',', ':')) + '\n').encode('ascii'))
                line = reader.readline(65538)
                if not line.endswith(b'\n') or len(line) > 65537 or not line.isascii():
                    raise RuntimeError('incomplete or oversized private reply')
                return json.loads(line)

            hello = exchange([1, 0, os.environ['MC_RENDER_TOKEN']])
            if len(hello) == 5 and hello[:4] == [1, 3, '', 0] and hello[4] == 'RendererLeaseBusy' and time.monotonic() < deadline:
                reader.close(); private.close(); private = None
                time.sleep(.05)
                continue
            if len(hello) != 4 or hello[:2] != [1, 0] or hello[3] != 0 or not isinstance(hello[2], str) or not hello[2]:
                raise RuntimeError('private shutdown authentication refused: ' + str(hello))
            break
        epoch = hello[2]
        sequence = 1
        if os.environ.get('MC_COOKING_PROTOCOL') == '1':
            def cooking(command, label, *, require_accepted=True):
                nonlocal sequence
                reply = exchange([1, 1, epoch, sequence, command])
                expected = [1, 8, epoch, sequence]
                sequence += 1
                if (not isinstance(reply, list) or len(reply) != 7 or reply[:4] != expected
                        or type(reply[4]) is not bool or not isinstance(reply[5], str)
                        or not isinstance(reply[6], list) or len(reply[6]) != 3):
                    raise RuntimeError('uncorrelated cooking shutdown reply: ' + str(reply))
                print(json.dumps({'event': label, 'epoch': epoch, 'sequence': expected[3],
                                  'accepted': reply[4], 'message': reply[5],
                                  'cooking': reply[6]}, separators=(',', ':')), flush=True)
                if require_accepted and reply[4] is not True:
                    raise RuntimeError('Cooking shutdown refused: ' + reply[5])
                return reply[6]

            # Inspect may refuse a stale target while retaining a valid menu
            # handle. Close has its own menu/player authority and must still run.
            current = cooking([15, 0], 'client.cooking-inspect', require_accepted=False)
            handle = current[0]
            if handle != [0]:
                if (not isinstance(handle, list) or len(handle) != 7 or handle[0] != 1
                        or type(handle[1]) is not int or not 0 < handle[1] < 4294967296):
                    raise RuntimeError('invalid current cooking handle: ' + str(handle))
                closed = cooking([18, handle[1]], 'client.cooking-close')
                if closed[0] != [0]:
                    raise RuntimeError('CookingClose did not acknowledge a closed handle')
        reply = exchange([1, 1, epoch, sequence, [10]])
        if len(reply) != 7 or reply[:4] != [1, 6, epoch, sequence] or not isinstance(reply[4], bool):
            raise RuntimeError('uncorrelated MenuClose reply: ' + str(reply))
        print(json.dumps({'event': 'client.menu-close', 'epoch': epoch, 'sequence': sequence,
                          'accepted': reply[4], 'message': reply[5], 'menu': reply[6]}, separators=(',', ':')), flush=True)
        if reply[4] is not True:
            raise RuntimeError('MenuClose refused: ' + str(reply[5]))
        menu = reply[6]
        if len(menu) != 8 or len(menu[0][3]) != 36 or len(menu[1]) != 7 or len(menu[2]) != 5 or menu[3:7] != [[[0]] * 4, [0], [0], False]:
            raise RuntimeError('MenuClose did not acknowledge an empty closed temporary menu')
        with socket.create_connection(('127.0.0.1', int(os.environ['MC_LIVE_PORT'])), timeout=5) as public:
            with public.makefile('rb') as source:
                def request(identity, operation, arguments):
                    public.sendall((json.dumps({'id': identity, 'op': operation, 'args': arguments}, separators=(',', ':')) + '\n').encode())
                    line = source.readline(65538)
                    if not line.endswith(b'\n') or len(line) > 65537:
                        raise RuntimeError('incomplete or oversized public save reply')
                    value = json.loads(line)
                    if value.get('id') != identity or value.get('ok') is not True:
                        raise RuntimeError(str(value.get('error', value)))
                    return value['result']
                request('close-authorize', 'session.open', {'mode': 'developer', 'token': os.environ['MC_DEV_TOKEN']})
                saved = request('close-save', 'world.save', {})
                if saved.get('status') != 'durable' or saved.get('published') is not True or saved.get('durable') is not True:
                    raise RuntimeError('save was not acknowledged durable: ' + str(saved))
                print(json.dumps({'event': 'client.save', 'path': os.environ['MC_WORLD_PATH'], 'result': saved}, separators=(',', ':')), flush=True)
                print('Saved ' + os.environ['MC_WORLD_PATH'] + ' (' + str(saved['bytes']) + ' bytes; durability acknowledged)', flush=True)
        return saved
    finally:
        if private is not None:
            reader.close(); private.close()


if __name__ == '__main__':
    try:
        transaction()
    except Exception as error:
        print('Close/save refused or failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
