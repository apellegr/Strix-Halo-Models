#!/usr/bin/env python3
"""Forward retired model ports to the consolidated model server (stdlib only).

Since 2026-11-13 Qwen3.8-27B on :8001 serves every use case (Home Assistant vision, family-assistant,
general chat, video). Clients still configured for the retired servers keep working through this:
  :8002 (was GLM-4.7-Flash)  -> :8001   plain TCP forward
  :8010 (was Qwen3-VL-30B)   -> :8001   HTTP forward that turns Qwen3.8's thinking OFF on chat requests

Why :8010 disables thinking: Home Assistant's LLM Vision integration (no options flow, so it can't be
reconfigured) caps replies at 120-200 tokens. With thinking on, the hidden reasoning used the whole budget
and the visible description came back empty or truncated. With thinking off, Qwen3.8's descriptions match
the old Qwen3-VL's detail. Family-assistant calls :8001 directly and keeps thinking on.
llama-server ignores the request's "model" name, so the old "qwen3-vl-30b" name is fine.

usage: legacy-port-forward.py   (ports fixed below)
"""
import asyncio, http.server, json, socketserver, threading, urllib.error, urllib.request

TARGET = 8001
TCP_PORTS = [8002]
NOTHINK_HTTP_PORT = 8010
HOP = {"connection", "keep-alive", "transfer-encoding", "content-length", "host"}

class NoThinkProxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _forward(self, method):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else None
        if body and method == "POST" and "chat/completions" in self.path:
            try:
                req = json.loads(body)
                kw = req.get("chat_template_kwargs") or {}
                kw["enable_thinking"] = False
                req["chat_template_kwargs"] = kw
                body = json.dumps(req).encode()
            except ValueError:
                pass  # not JSON: pass through untouched
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        up = urllib.request.Request(f"http://127.0.0.1:{TARGET}{self.path}", data=body, method=method, headers=headers)
        try:
            resp = urllib.request.urlopen(up, timeout=900)
        except urllib.error.HTTPError as e:
            resp = e
        except OSError as e:
            self.send_error(502, f"upstream :{TARGET} unreachable: {e}")
            return
        self.send_response(resp.status)
        for k, v in resp.headers.items():
            if k.lower() not in HOP:
                self.send_header(k, v)
        self.send_header("Transfer-Encoding", "chunked")  # works for both plain and streamed (SSE) replies
        self.end_headers()
        while chunk := resp.read1(65536) if hasattr(resp, "read1") else resp.read(65536):
            self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")
        print(f"{self.client_address[0]} -> :{NOTHINK_HTTP_PORT} {method} {self.path} -> :{TARGET} {resp.status} (thinking off)", flush=True)

    def do_POST(self): self._forward("POST")
    def do_GET(self): self._forward("GET")
    def log_message(self, *a): pass

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass

async def tcp_handle(c_reader, c_writer):
    peer = c_writer.get_extra_info("peername")
    print(f"{peer[0] if peer else '?'} -> :{c_writer.get_extra_info('sockname')[1]} -> :{TARGET} (tcp)", flush=True)
    try:
        u_reader, u_writer = await asyncio.open_connection("127.0.0.1", TARGET)
    except OSError as e:
        print(f"connect to :{TARGET} failed: {e}", flush=True)
        c_writer.close()
        return
    await asyncio.gather(pipe(c_reader, u_writer), pipe(u_reader, c_writer))

async def tcp_main():
    servers = [await asyncio.start_server(tcp_handle, "0.0.0.0", p) for p in TCP_PORTS]
    for p in TCP_PORTS:
        print(f"forwarding :{p} -> 127.0.0.1:{TARGET} (tcp)", flush=True)
    await asyncio.gather(*(s.serve_forever() for s in servers))

if __name__ == "__main__":
    threading.Thread(target=lambda: asyncio.run(tcp_main()), daemon=True).start()
    print(f"forwarding :{NOTHINK_HTTP_PORT} -> 127.0.0.1:{TARGET} (http, thinking off)", flush=True)
    Server(("0.0.0.0", NOTHINK_HTTP_PORT), NoThinkProxy).serve_forever()
