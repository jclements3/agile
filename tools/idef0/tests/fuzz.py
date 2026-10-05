#!/usr/bin/env python3
"""fuzz.py N -- mutate dronecorp.md N ways; compare python vs perl on
lint, links, fmt --number, html. Mutations: char typos in names and
link paths, dropped lines, indentation shifts, suffix swaps, duplicated
lines, trailing comments/docs."""
import random, subprocess, sys
src = open("examples/dronecorp/dronecorp.md", encoding="utf-8").read().splitlines()
N = int(sys.argv[1]); fails = 0
alpha = "abcdefghijklmnopqrstuvwxyz &-|<>#é"
def mutate(lines, rng):
    L = list(lines)
    for _ in range(rng.randint(1, 6)):
        i = rng.randrange(len(L)); s = L[i]; k = rng.randrange(8)
        if k == 0 and len(s) > 4:
            j = rng.randrange(2, len(s)); L[i] = s[:j] + rng.choice(alpha) + s[j+1:]
        elif k == 1 and len(s) > 4:
            j = rng.randrange(2, len(s)); L[i] = s[:j] + s[j+1:]
        elif k == 2: del L[i]
        elif k == 3: L[i] = " " * rng.choice([1, 2, 3]) + s
        elif k == 4: L[i] = s.replace("1 ", rng.choice(["# ", "2 ", "0 ", "11 ", "3. "]), 1)
        elif k == 5: L.insert(i, s)
        elif k == 6: L[i] = s + rng.choice(["  # c", "  ## d **b**", " ##", "\t#x"])
        elif k == 7 and "|" in s:
            j = s.rindex("|"); L[i] = s[:j+1] + s[j+2:] if len(s) > j + 2 else s
    return L
for seed in range(N):
    rng = random.Random(seed)
    open("/tmp/m.md", "w", encoding="utf-8").write("\n".join(mutate(src, rng)) + "\n")
    for cmd in (["lint"], ["links"], ["fmt", "--number"], ["html"]):
        a = subprocess.run(["python3", "./reference/idef0"] + cmd + ["/tmp/m.md"], capture_output=True)
        b = subprocess.run(["perl", "./idef0.pl"] + cmd + ["/tmp/m.md"], capture_output=True)
        if (a.stdout, a.stderr, a.returncode) != (b.stdout, b.stderr, b.returncode):
            fails += 1; print("FAIL seed", seed, cmd)
            import shutil; shutil.copy("/tmp/m.md", f"/tmp/fail{seed}.md"); break
print(f"fuzz: {N} mutants x 4 commands, {fails} failing mutants")
