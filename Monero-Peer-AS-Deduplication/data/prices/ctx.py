import re, sys
f, pat = sys.argv[1], sys.argv[2]; n = int(sys.argv[3]) if len(sys.argv) > 3 else 3
t = open(f + ".txt", errors="ignore").read()
for i, m in enumerate(re.finditer(pat, t, re.I)):
    if i >= n: break
    print("  >", t[max(0, m.start()-120):m.end()+120])
