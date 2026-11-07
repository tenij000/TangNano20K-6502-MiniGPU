import argparse
import os
import serial
import sys
from sd_tools import SDCARD_DIR, upload_file_to_sdcard, find_tang_port


def main():
    os.makedirs(SDCARD_DIR, exist_ok=True)

    # Als sd_copy.py zonder argumenten (of met --gui / -g) wordt gestart -> open direct de grafische SD-Uploader GUI!
    if len(sys.argv) == 1 or "--gui" in sys.argv or "-g" in sys.argv:
        from sd_gui import launch_gui
        launch_gui()
        return

    parser = argparse.ArgumentParser(
        description="MiniGPU SD-Kaart & SDRAM-Disk Uploader (GUI + CLI)"
    )
    parser.add_argument("target", nargs="?", help="Pad naar .asm, .bas, .txt, .bin bestand of map")
    parser.add_argument("--port", "-p", default=None, help="COM-poort (bijv. COM6)")
    parser.add_argument("--drive", "-d", type=int, default=None, help="Doel-station op SD/SDRAM (0..3)")
    parser.add_argument("--sdram", action="store_true", help="Sla op naar 4 MB SDRAM-Disk i.p.v. MicroSD")
    parser.add_argument("--sd", action="store_true", help="Sla op naar MicroSD-kaart (standaard)")
    parser.add_argument("--name", "-n", default=None, help="Aangepaste bestandsnaam op de SD-kaart (max 14 tekens)")
    parser.add_argument("--run", "-r", action="store_true", help="Start programma direct na uploaden (RUN / BRUN)")
    parser.add_argument("--cli", action="store_true", help="Interactief tekstmenu in de terminal")
    args = parser.parse_args()

    port = args.port or find_tang_port("COM6")
    media = "SDRAM" if args.sdram else "SD"

    try:
        ser = serial.Serial(port, 115200, timeout=0.5)
    except Exception as e:
        print(f"Kan {port} niet openen (sluit eerst basic_terminal.py of druk op F5 in basic_terminal.py!): {e}")
        sys.exit(1)

    try:
        if args.target and not args.cli:
            target = args.target
            if not os.path.exists(target):
                target = os.path.join(SDCARD_DIR, target)
            if os.path.isdir(target):
                files = sorted(
                    f for f in os.listdir(target)
                    if os.path.splitext(f)[1].lower() in (".bas", ".asm", ".s", ".bin", ".txt", ".img", ".png", ".jpg", ".jpeg", ".bmp", ".gif")
                )
                for fn in files:
                    upload_file_to_sdcard(
                        ser,
                        os.path.join(target, fn),
                        run_after=False,
                        media=media,
                        drive=args.drive,
                    )
            else:
                upload_file_to_sdcard(
                    ser,
                    target,
                    run_after=args.run,
                    sd_name_override=args.name,
                    media=media,
                    drive=args.drive,
                )
        else:
            files = sorted(
                f for f in os.listdir(SDCARD_DIR)
                if os.path.splitext(f)[1].lower() in (".bas", ".asm", ".s", ".bin", ".txt", ".img", ".png", ".jpg", ".jpeg", ".bmp", ".gif")
            )
            print(f"Bestanden in {SDCARD_DIR}:")
            for i, fn in enumerate(files, 1):
                print(f"  [{i}] {fn}")
            choice = input("Kies nummer (of 'A' voor alles, bijv. '2R' om direct te starten): ").strip().upper()
            if choice == "A":
                for fn in files:
                    upload_file_to_sdcard(
                        ser,
                        os.path.join(SDCARD_DIR, fn),
                        run_after=False,
                        media=media,
                        drive=args.drive,
                    )
            elif choice:
                run_after = choice.endswith("R") or args.run
                idx = int(choice[:-1] if choice.endswith("R") else choice) - 1
                upload_file_to_sdcard(
                    ser,
                    os.path.join(SDCARD_DIR, files[idx]),
                    run_after=run_after,
                    sd_name_override=args.name,
                    media=media,
                    drive=args.drive,
                )
    finally:
        ser.close()


if __name__ == "__main__":
    main()
