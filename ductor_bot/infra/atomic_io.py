"""Atomic file write primitives.

All persistent writes in the codebase should funnel through these helpers.
They use ``tempfile.mkstemp`` + ``os.replace`` for POSIX-atomic semantics:
a partial write can never leave a corrupt target file.
"""

from __future__ import annotations

import contextlib
import os
import stat
import tempfile
from pathlib import Path


def _preserve_mode(target: Path, fd: int) -> None:
    """Copy *target*'s permission mode to the open file descriptor *fd*.

    When the target file exists, its mode is applied to the temp file
    before ``os.replace``.  This keeps the ACL mask (derived from the
    group permission bits) intact — without it, ``mkstemp``'s default
    ``0600`` would zero the mask and disable all non-owner ACL entries.
    """
    try:
        mode = target.stat().st_mode
        os.fchmod(fd, stat.S_IMODE(mode))
    except (OSError, ValueError):
        pass


def atomic_text_save(path: Path, content: str, *, encoding: str = "utf-8") -> None:
    """Write *content* to *path* atomically via temp file + rename.

    Creates parent directories if they don't exist.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_str = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    tmp = Path(tmp_str)
    try:
        _preserve_mode(path, fd)
        with os.fdopen(fd, "w", encoding=encoding) as f:
            f.write(content)
        tmp.replace(path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.close(fd)
        tmp.unlink(missing_ok=True)
        raise


def atomic_bytes_save(path: Path, data: bytes) -> None:
    """Write *data* to *path* atomically via temp file + rename.

    Creates parent directories if they don't exist.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_str = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    tmp = Path(tmp_str)
    try:
        _preserve_mode(path, fd)
        os.write(fd, data)
        os.close(fd)
        tmp.replace(path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.close(fd)
        tmp.unlink(missing_ok=True)
        raise
