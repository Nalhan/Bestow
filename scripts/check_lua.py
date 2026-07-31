#!/usr/bin/env python3
"""Lua 5.1 Lexer and Syntax Checker for Bestow addon files."""

from __future__ import annotations

import sys
import re
from pathlib import Path


class LuaSyntaxError(Exception):
    def __init__(self, filename: str, line: int, col: int, message: str):
        super().__init__(f"{filename}:{line}:{col}: {message}")
        self.filename = filename
        self.line = line
        self.col = col
        self.message = message


def tokenize_lua(code: str, filename: str):
    """Tokenize Lua 5.1 source code with line and column tracking."""
    i = 0
    length = len(code)
    line = 1
    col = 1

    tokens = []

    while i < length:
        ch = code[i]

        # Whitespace
        if ch == '\n':
            line += 1
            col = 1
            i += 1
            continue
        elif ch in ' \t\r\f\v':
            col += 1
            i += 1
            continue

        # Comments
        if code.startswith('--', i):
            start_line, start_col = line, col
            i += 2
            col += 2
            # Check for long comment --[[ or --[=[
            match = re.match(r'^\[(=*)\[', code[i:])
            if match:
                eq_len = len(match.group(1))
                close_delim = ']' + '=' * eq_len + ']'
                end_pos = code.find(close_delim, i + len(match.group(0)))
                if end_pos == -1:
                    raise LuaSyntaxError(filename, start_line, start_col, "Unclosed block comment")
                comment_text = code[i:end_pos + len(close_delim)]
                line += comment_text.count('\n')
                if '\n' in comment_text:
                    col = len(comment_text) - comment_text.rfind('\n')
                else:
                    col += len(comment_text)
                i = end_pos + len(close_delim)
            else:
                # Line comment
                nl = code.find('\n', i)
                if nl == -1:
                    break
                col = 1
                line += 1
                i = nl + 1
            continue

        # Long strings [[ ... ]] or [=[ ... ]=]
        match_long_str = re.match(r'^\[(=*)\[', code[i:])
        if match_long_str:
            start_line, start_col = line, col
            eq_len = len(match_long_str.group(1))
            close_delim = ']' + '=' * eq_len + ']'
            content_start = i + len(match_long_str.group(0))
            end_pos = code.find(close_delim, content_start)
            if end_pos == -1:
                raise LuaSyntaxError(filename, start_line, start_col, "Unclosed long string literal")
            full_str = code[i:end_pos + len(close_delim)]
            tokens.append(('STRING', full_str, start_line, start_col))
            line += full_str.count('\n')
            if '\n' in full_str:
                col = len(full_str) - full_str.rfind('\n')
            else:
                col += len(full_str)
            i = end_pos + len(close_delim)
            continue

        # Short strings '...' or "..."
        if ch in ('"', "'"):
            quote = ch
            start_line, start_col = line, col
            i += 1
            col += 1
            str_chars = [quote]
            escaped = False
            while i < length:
                c = code[i]
                str_chars.append(c)
                if c == '\n':
                    raise LuaSyntaxError(filename, start_line, start_col, "Unclosed string literal (unfinished line)")
                if escaped:
                    escaped = False
                elif c == '\\':
                    escaped = True
                elif c == quote:
                    i += 1
                    col += 1
                    break
                i += 1
                col += 1
            else:
                raise LuaSyntaxError(filename, start_line, start_col, "Unclosed string literal")
            tokens.append(('STRING', ''.join(str_chars), start_line, start_col))
            continue

        # Identifiers & Keywords
        if ch.isalpha() or ch == '_':
            start_line, start_col = line, col
            match = re.match(r'^[a-zA-Z0-9_]+', code[i:])
            tok_str = match.group(0)
            i += len(tok_str)
            col += len(tok_str)
            tokens.append(('WORD', tok_str, start_line, start_col))
            continue

        # Numbers
        if ch.isdigit() or (ch == '.' and i + 1 < length and code[i + 1].isdigit()):
            start_line, start_col = line, col
            match = re.match(r'^(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)', code[i:])
            tok_str = match.group(0)
            i += len(tok_str)
            col += len(tok_str)
            tokens.append(('NUMBER', tok_str, start_line, start_col))
            continue

        # Multi-char operators
        start_line, start_col = line, col
        for op in ('...', '..', '==', '~=', '<=', '>=', '::'):
            if code.startswith(op, i):
                tokens.append(('OP', op, start_line, start_col))
                i += len(op)
                col += len(op)
                break
        else:
            tokens.append(('OP', ch, start_line, start_col))
            i += 1
            col += 1

    return tokens


KEYWORDS_BLOCK_OPEN = {'if', 'do', 'function', 'repeat'}
KEYWORDS_BLOCK_CLOSE = {'end', 'until'}


def check_lua_syntax(code: str, filename: str) -> None:
    tokens = tokenize_lua(code, filename)
    stack = []
    paren_stack = []

    i = 0
    num_tokens = len(tokens)

    while i < num_tokens:
        tok_type, val, l, c = tokens[i]

        # Brackets and Parentheses
        if val in ('(', '[', '{'):
            paren_stack.append((val, l, c))
        elif val in (')', ']', '}'):
            expected = {'(': ')', '[': ']', '{': '}'}
            if not paren_stack:
                raise LuaSyntaxError(filename, l, c, f"Unexpected closing bracket '{val}'")
            opener, ol, oc = paren_stack.pop()
            if expected[opener] != val:
                raise LuaSyntaxError(
                    filename, l, c,
                    f"Mismatched bracket: expected '{expected[opener]}' for '{opener}' at line {ol}, found '{val}'"
                )

        # Block control flow
        if tok_type == 'WORD':
            if val == 'function':
                stack.append(('function', l, c))
            elif val == 'if':
                stack.append(('if', l, c))
            elif val == 'do':
                # 'while ... do' and 'for ... do' share the same 'do' block
                # Only push 'do' if top of stack isn't already 'while' or 'for'
                stack.append(('do', l, c))
            elif val == 'repeat':
                stack.append(('repeat', l, c))
            elif val == 'until':
                if not stack:
                    raise LuaSyntaxError(filename, l, c, "Unexpected 'until' without matching 'repeat'")
                top_kind, top_l, top_c = stack.pop()
                if top_kind != 'repeat':
                    raise LuaSyntaxError(
                        filename, l, c,
                        f"Mismatched block end: expected 'until' to close 'repeat' (line {top_l}), but closed '{top_kind}'"
                    )
            elif val == 'end':
                if not stack:
                    raise LuaSyntaxError(filename, l, c, "Unexpected 'end' without matching open block")
                top_kind, top_l, top_c = stack.pop()
                if top_kind == 'repeat':
                    raise LuaSyntaxError(
                        filename, l, c,
                        f"Mismatched block end: 'repeat' at line {top_l} must be closed with 'until', not 'end'"
                    )

        i += 1

    if paren_stack:
        opener, l, c = paren_stack[-1]
        raise LuaSyntaxError(filename, l, c, f"Unclosed bracket '{opener}'")

    if stack:
        kind, l, c = stack[-1]
        raise LuaSyntaxError(filename, l, c, f"Unclosed '{kind}' block")


def check_file(path: Path) -> bool:
    try:
        code = path.read_text(encoding="utf-8")
        check_lua_syntax(code, path.name)
        return True
    except LuaSyntaxError as err:
        print(f"LINT ERROR: {err}", file=sys.stderr)
        return False
    except Exception as exc:
        print(f"LINT EXCEPTION: {path.name}: {exc}", file=sys.stderr)
        return False


if __name__ == "__main__":
    if len(sys.argv) > 1:
        paths = [Path(p) for p in sys.argv[1:]]
    else:
        root = Path(__file__).resolve().parents[1]
        paths = list(root.rglob("*.lua"))

    ok = True
    for p in sorted(paths):
        if ".git" in p.parts:
            continue
        if not check_file(p):
            ok = False

    if not ok:
        sys.exit(1)
    print(f"Lua syntax check passed on {len(paths)} files.")
