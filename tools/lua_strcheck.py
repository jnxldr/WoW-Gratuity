r"""Flags short Lua strings that contain a raw newline (real Lua: "unfinished string") or an invalid escape such as
"\A" (real Lua: "invalid escape sequence"); luaparser accepts both.
Usage: python -I tools/lua_strcheck.py <file.lua>...  (exit 1 if any found)"""
import sys, re
bad = 0
for path in sys.argv[1:]:
    s = open(path, encoding="utf-8").read()
    i, line, n = 0, 1, len(s)
    while i < n:
        c = s[i]
        if c == "\n":
            line += 1; i += 1
        elif s.startswith("--", i):
            m = re.match(r"--\[(=*)\[", s[i:])
            if m:
                end = s.find("]" + m.group(1) + "]", i)
                line += s.count("\n", i, end); i = end + 2 + len(m.group(1))
            else:
                end = s.find("\n", i); i = n if end < 0 else end
        elif c == "[" and re.match(r"\[(=*)\[", s[i:]):
            m = re.match(r"\[(=*)\[", s[i:])
            end = s.find("]" + m.group(1) + "]", i)
            line += s.count("\n", i, end); i = end + 2 + len(m.group(1))
        elif c in "\"'":
            start, j = line, i + 1
            while j < n and s[j] != c:
                if s[j] == "\\":
                    j += 1
                    if j < n and s[j] not in "abfnrtvz\\\"'\n0123456789xu":
                        print(f"{path}:{line}: invalid escape \\{s[j]} in string"); bad += 1
                elif s[j] == "\n":
                    print(f"{path}:{start}: raw newline in string"); bad += 1; line += 1
                j += 1
            i = j + 1
        else:
            i += 1
sys.exit(1 if bad else 0)
