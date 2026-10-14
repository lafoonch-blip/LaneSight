"""python -m lanesight_runner [--watch ~/Downloads] [--data ~/LaneSightData] [--port 8765] [--no-open] [--no-speech]"""
import argparse, os, shutil, sys, threading, webbrowser

def main():
    ap = argparse.ArgumentParser(prog='lanesight_runner', description='LaneSight at-lane runner')
    ap.add_argument('--watch', default='~/Downloads', help='folder AirDropped clips land in (default ~/Downloads)')
    ap.add_argument('--data', default=os.environ.get('LANESIGHT_DATA', '~/LaneSightData'),
                    help='where clips, results and the database are stored (default ~/LaneSightData)')
    ap.add_argument('--port', type=int, default=8765)
    ap.add_argument('--no-open', action='store_true', help="don't open the browser")
    ap.add_argument('--no-speech', action='store_true', help="don't read results aloud")
    a = ap.parse_args()
    missing = [t for t in ('ffmpeg', 'ffprobe') if not shutil.which(t)]
    if missing:
        sys.exit(f"Missing {', '.join(missing)}. Install with: brew install ffmpeg")
    try:
        import uvicorn
        from .server import create_app
    except ImportError as e:
        sys.exit(f"Missing runner dependencies ({e.name}). Install with: python3 -m pip install -e '.[runner]'")
    from .core import Runner, Speaker
    watch = os.path.expanduser(a.watch)
    if not os.path.isdir(watch): sys.exit(f'Watch folder not found: {watch}')
    runner = Runner(a.data, watch_dir=watch, speaker=Speaker(enabled=not a.no_speech))
    runner.start()
    url = f'http://127.0.0.1:{a.port}/'
    print(f'LaneSight runner: {url}\n  watching {watch}\n  data in  {runner.data_dir}')
    if runner.watch_error: print('  WARNING:', runner.watch_error)
    if not a.no_open: threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    uvicorn.run(create_app(runner), host='127.0.0.1', port=a.port, log_level='warning')

if __name__ == '__main__':
    main()
