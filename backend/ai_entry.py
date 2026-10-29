"""Entry point used by the bundled isolated Python interpreter (-I -B)."""
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import certifi
os.environ.setdefault("SSL_CERT_FILE", certifi.where())

from app.ai_runtime.server import main

if __name__ == "__main__":
    main()
