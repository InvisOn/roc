import sys,re
# Print the plan table (#, Pull request, Where it sits) with step `cur` in bold.
src, cur = sys.argv[1], sys.argv[2]
rows=[l for l in open(src).read().split('\n') if re.match(r'^\| \d+ \|', l)]
out=['| # | Pull request | Where it sits |','|---|---|---|']
for r in rows:
    c=[x.strip() for x in r.strip('|').split('|')]
    # Drop draft numbers: they are our notes, not upstream's.
    pr=re.sub(r' \(drafts? [0-9, and]+\)','',c[1])
    if c[0]==cur: out.append(f'| **{c[0]}** | **{pr}** (this PR) | **{c[2]}** |')
    else: out.append(f'| {c[0]} | {pr} | {c[2]} |')
print('\n'.join(out))
