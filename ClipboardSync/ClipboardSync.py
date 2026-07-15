import socket
import threading
import time
import sys
import os
import subprocess
import hashlib

APP_VERSION="v0.1.5"

# Check arguments length and validity
if len(sys.argv) < 2 or sys.argv[1] not in ["win", "linux"]:
    print("Usage: python main.py [win|linux]")
    # Exit if arguments are invalid
    sys.exit(1)

ROLE = sys.argv[1]
TARGET_ROLE = "linux" if ROLE == "win" else "win"

# Import required modules based on environment
if ROLE == "win":
    try:
        import pyperclip
        from PIL import ImageGrab
    except ImportError:
        print("[ERR] Missing libraries on Windows. Run: pip install pyperclip Pillow")
        # Exit if dependencies are missing
        sys.exit(1)

# Configure port routing based on role
if ROLE == "win":
    LISTEN_PORT = 3204
    SEND_PORT = 3205
else:
    LISTEN_PORT = 3205
    SEND_PORT = 3204

BUFFER_SIZE = 65536
lock = threading.Lock()
last_clipboard_hash = ""

# Define Handshake Magic Strings
MAGIC_HELLO = f">>>>>>>Hello-From-{ROLE.upper()}-Server>>>>>>>"
MAGIC_ACK = f"<<<<<<<<Hello-From-{ROLE.upper()}-Server<<<<<<<<"
EXPECTED_ACK = f"<<<<<<<<Hello-From-{TARGET_ROLE.upper()}-Server<<<<<<<<"

"""
/*
 * @brief  Receives exactly n bytes from the socket.
 * @param  sock The socket object.
 * @param  n    The number of bytes to receive.
 * @return The complete byte array received, or None if connection lost.
 */
"""
def recvall(sock, n):
    data = bytearray()
    while len(data) < n:
        packet = sock.recv(min(n - len(data), BUFFER_SIZE))
        if not packet:
            # Connection closed prematurely
            return None
        data.extend(packet)
    # Return full data buffer
    return bytes(data)

"""
/*
 * @brief  Sets the system clipboard text or image.
 * @param  dtype The data type ("TEXT" or "IMAG").
 * @param  data  The raw bytes to copy to the clipboard.
 */
"""
def set_clipboard(dtype, data):
    if ROLE == "linux":
        try:
            env = os.environ.copy()
            if "DISPLAY" not in env:
                env["DISPLAY"] = ":0"
            
            if dtype == "IMAG":
                p = subprocess.Popen(['xclip', '-selection', 'clipboard', '-t', 'image/png', '-i'], stdin=subprocess.PIPE, env=env)
            else:
                p = subprocess.Popen(['xclip', '-selection', 'clipboard', '-i'], stdin=subprocess.PIPE, env=env)
                
            p.communicate(input=data)
        except FileNotFoundError:
            print("[ERR] Please run: sudo apt install xclip")
        except Exception as e:
            print(f"[ERR] set_clipboard: {e}")
    else:
        if dtype == "IMAG":
            try:
                # Save raw PNG bytes to a temporary file
                temp_path = os.path.join(os.environ.get('TEMP', '.'), 'clip_sync_temp.png')
                with open(temp_path, 'wb') as f:
                    f.write(data)
                
                # Use powershell to load the image into the Windows Clipboard
                ps_cmd = f"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::SetImage([System.Drawing.Image]::FromFile('{temp_path}'))"
                
                # HIDE_WINDOW flag equivalent for cross-platform safety
                creation_flags = 0x08000000 if sys.platform == "win32" else 0
                subprocess.run(["powershell", "-command", ps_cmd], creationflags=creation_flags)
            except Exception as e:
                print(f"[ERR] Windows Image Set: {e}")
        else:
            pyperclip.copy(data.decode('utf-8', errors='ignore'))

"""
/*
 * @brief  Gets the current text or image from the system clipboard.
 * @return A tuple containing (Data_Type: "TEXT"|"IMAG"|"NONE", Raw_Bytes).
 */
"""
def get_clipboard():
    if ROLE == "linux":
        try:
            env = os.environ.copy()
            if "DISPLAY" not in env:
                env["DISPLAY"] = ":0"
            
            # Check what targets are available in clipboard
            targets = subprocess.check_output(['xclip', '-selection', 'clipboard', '-t', 'TARGETS', '-o'], env=env, stderr=subprocess.DEVNULL).decode('utf-8')
            
            if 'image/png' in targets:
                img_data = subprocess.check_output(['xclip', '-selection', 'clipboard', '-t', 'image/png', '-o'], env=env, stderr=subprocess.DEVNULL)
                # Return image payload
                return ("IMAG", img_data)
            else:
                txt_data = subprocess.check_output(['xclip', '-selection', 'clipboard', '-o'], env=env, stderr=subprocess.DEVNULL)
                # Return text payload
                return ("TEXT", txt_data)
        except Exception:
            # Return none on read failure
            return ("NONE", b"")
    else:
        # Check for Image first
        try:
            img = ImageGrab.grabclipboard()
            if img is not None and not isinstance(img, list):
                import io
                with io.BytesIO() as output:
                    img.save(output, format="PNG")
                    # Return image payload
                    return ("IMAG", output.getvalue())
        except Exception:
            pass

        # Fallback to Text
        try:
            txt = pyperclip.paste()
            if txt:
                # Return text payload
                return ("TEXT", txt.encode('utf-8'))
        except Exception:
            pass
            
        # Return none if empty
        return ("NONE", b"")

"""
/*
 * @brief  Performs a single handshake attempt with the peer.
 * @return True if handshake successful, False otherwise.
 */
"""
def perform_handshake():
    try:
        test_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        test_sock.settimeout(2.0)
        test_sock.connect(('127.0.0.1', SEND_PORT))
        
        # Send Handshake
        test_sock.sendall(MAGIC_HELLO.encode('utf-8'))
        
        # Wait for Acknowledgment
        response = test_sock.recv(BUFFER_SIZE).decode('utf-8', errors='ignore')
        test_sock.close()
        
        if response == EXPECTED_ACK:
            return True
    except Exception:
        pass
    return False

"""
/*
 * @brief  Server thread to listen for incoming clipboard data and handshakes.
 */
"""
def listen_server():
    global last_clipboard_hash
    
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    try:
        server_socket.bind(('127.0.0.1', LISTEN_PORT))
        server_socket.listen(1)
        print(f"[INF] {ROLE.upper()} is listening on port {LISTEN_PORT}...")
    except Exception as e:
        print(f"[ERR] Cannot bind to port {LISTEN_PORT}: {e}")
        # Exit if server port cannot be bound
        sys.exit(1)

    while True:
        try:
            conn, addr = server_socket.accept()
            
            # Read first 14 bytes to check protocol (Handshake vs Data Header)
            header = conn.recv(14)
            if not header:
                conn.close()
                continue
                
            header_str = header.decode('utf-8', errors='ignore')
            
            # Intercept Handshake Message
            if header_str.startswith(">>>>>>>Hello-F"):
                conn.sendall(MAGIC_ACK.encode('utf-8'))
                conn.close()
                continue 

            # Normal Data Protocol: [TYPE:4][SIZE:10][HASH:32]
            if len(header) == 14 and (header.startswith(b'TEXT') or header.startswith(b'IMAG')):
                dtype = header[:4].decode('utf-8')
                dsize = int(header[4:].decode('utf-8'))
                
                # Fetch the MD5 hash (32 bytes)
                hash_bytes = recvall(conn, 32)
                if not hash_bytes:
                    conn.close()
                    continue
                expected_hash = hash_bytes.decode('utf-8')
                
                print(f"[DEBUG] Incoming {dtype}. Size: ~{dsize/1024/1024:.2f} MB. Hash: {expected_hash[:8]}...")
                
                # Fetch payload
                data = recvall(conn, dsize)
                if data:
                    actual_hash = hashlib.md5(data).hexdigest()
                    if actual_hash == expected_hash:
                        with lock:
                            last_clipboard_hash = actual_hash
                            set_clipboard(dtype, data)
                        print(f"[SYNC] Extracted and copied {dtype} successfully!")
                    else:
                        print(f"[ERR] Data integrity check failed! Expected {expected_hash}, got {actual_hash}")
            
            conn.close()
        except Exception as e:
            print(f"[ERR] In server loop: {e}")

"""
/*
 * @brief  Client thread to monitor local clipboard, handle heartbeats, and send changes.
 */
"""
def monitor_local_clipboard():
    global last_clipboard_hash
    
    print(f"[INF] Waiting for peer application on port {SEND_PORT}...")
    while not perform_handshake():
        time.sleep(2)
    print(f"[INF] Handshake successful! Link established.")
    
    last_handshake_time = time.time()
    
    dtype, current_data = get_clipboard()
    if dtype != "NONE":
        last_clipboard_hash = hashlib.md5(current_data).hexdigest()
        
    print(f"[INF] Monitoring local clipboard, ready to send...")
    
    while True:
        time.sleep(1.0) # Polling delay
        
        # Periodic Heartbeat every 60 seconds
        if time.time() - last_handshake_time > 60:
            if perform_handshake():
                last_handshake_time = time.time()
            else:
                print(f"[WRN] Peer lost on port {SEND_PORT}. Pausing sync...")
                while not perform_handshake():
                    time.sleep(2)
                print(f"[INF] Peer reconnected! Resuming sync.")
                last_handshake_time = time.time()

        dtype, current_data = get_clipboard()

        if dtype == "NONE":
            continue
            
        current_hash = hashlib.md5(current_data).hexdigest()

        # Prevent Echo: Only send if the clipboard hash is new
        if current_hash != last_clipboard_hash:
            with lock:
                last_clipboard_hash = current_hash
            
            payload_size = len(current_data)
            # Create header: [TYPE:4][SIZE:10][HASH:32]
            header = f"{dtype}{payload_size:010d}{current_hash}".encode('utf-8')
            
            try:
                client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                # Allow generous timeout for large transfers
                client_socket.settimeout(60.0) 
                client_socket.connect(('127.0.0.1', SEND_PORT))
                
                print(f"[SYNC] Sending {dtype}, Size: ~{payload_size/1024/1024:.2f} MB, Hash: {current_hash[:8]}...")
                client_socket.sendall(header + current_data)
                
                client_socket.close()
                print(f"[SYNC] Transmission complete.")
            except Exception as e:
                print(f"[ERR] Transmission failed: {e}")

if __name__ == "__main__":

    print(f"\n[ClipboardSync.{APP_VERSION}]")

    t1 = threading.Thread(target=listen_server, daemon=True)
    t2 = threading.Thread(target=monitor_local_clipboard, daemon=True)
    
    t1.start()
    t2.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[INF] Exiting Clipboard Sync.")