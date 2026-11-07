import socket
import sys
import threading

HOST = "192.168.178.200"
PORT = 23


def rx_thread(sock: socket.socket):
    try:
        while True:
            data = sock.recv(1024)
            if not data:
                print("\n[Verbinding gesloten door 6502]")
                break
            sys.stdout.write("\r" + data.decode("ascii", "ignore") + "PC> ")
            sys.stdout.flush()
    except Exception:
        pass


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else HOST
    port = int(sys.argv[2]) if len(sys.argv) > 2 else PORT
    print(f"Verbinden met DONDERDAG 6502 Telnet Server op {host}:{port} ...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5.0)
    sock.connect((host, port))
    sock.settimeout(None)
    print("Verbonden! Typ een bericht en druk op Enter (of 'exit' om te stoppen).")

    t = threading.Thread(target=rx_thread, args=(sock,), daemon=True)
    t.start()

    try:
        while True:
            line = input("PC> ")
            if line.strip().lower() in ("exit", "quit"):
                break
            sock.sendall((line + "\r\n").encode("ascii", "ignore"))
    except (KeyboardInterrupt, EOFError):
        pass
    finally:
        sock.close()


if __name__ == "__main__":
    main()
