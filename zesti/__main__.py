"""Allow ``python3 -m zesti`` to run the canonical CLI."""

import sys

from zesti.cli import main

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
