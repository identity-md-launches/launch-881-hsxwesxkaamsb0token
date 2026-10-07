# HX adversarial tests

The accepted `LaunchToken.t.sol` covers metadata, deployment, basic ERC-20 behavior,
factory-style allocation, and the absence of common administrative entry points.
The additional suites test the existing implementation without changing source,
dependencies, or configuration.

`LaunchToken.adversarial.t.sol` adds deterministic zero/one/full-supply/maximum
boundaries, allowance isolation between owners and spenders, revocation and replay,
delegated self-transfers, and rejection of ETH attached to ERC-20 calls. Five fuzz
properties check transfer round trips, approval idempotence/replacement, split
spending, rollback of finite allowances on insufficient balance, and overdraws
to oneself. New fuzz inputs use constructive bounds without discarded assumptions.

`LaunchToken.invariant.t.sol` drives four holders through transfers, approvals,
delegated transfers, overdraw attempts, excessive allowance spending, and invalid
zero-address operations. The token contract is also a possible recipient; tokens
sent there remain included in accounting. Only the handler's six action selectors
are targeted. Successful amounts include zero, one wei, the whole available amount,
and partial amounts. Approval sequences include revocation, arbitrary uint256
amounts, maximum finite allowance, and infinite allowance.

After every action, the suite checks:

- Supply remains exactly 1,000,000,000 HX and equals all tracked holdings.
- Each account's initial allocation plus recorded receipts equals its balance plus
  recorded payments. Ghost flows use successful requested amounts, not token reads.
- All 16 owner/spender pairs match approval and successful spending history;
  failed transfers cannot consume an allowance.

Expected failures are checked with exact custom errors. Unexpected handler reverts
fail the campaign. A deterministic witness exercises every rejection branch and
positive direct/delegated transfers so handler reachability does not rely on luck.
No token storage is edited, no balances are fabricated with a token cheatcode, and
no environment variables, RPC, or forks are used.

Inline defaults are 1,000 cases per new fuzz property and 256 invariant runs of
128 actions. Reproduce offline from the repository root; the output/cache overrides
keep generated files inside disposable scratch space:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache --fuzz-seed 0x20261008 --fuzz-runs 2048
forge fmt --check
```

The tests establish properties of the local token. They do not verify a network
factory, live deployment, pool economics, manifest, or frontend. No source defect
was reproduced during this testing contribution.
