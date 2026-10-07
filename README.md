# HS XWesXkAAMSB0 (HX)

This is the contract implementation for the HX token-only IMD project launch. The target is **Ethereum mainnet (chain ID 1)**. Deployment, the separate `launch.json`, source publication, attestation, and the IPFS frontend are subsequent workflow contributions. This repository does not claim a live deployment or verified contract address.

## Token rules

`src/LaunchToken.sol:LaunchToken` is a plain OpenZeppelin ERC-20 with a **nonpayable, zero-argument constructor**. It mints exactly **1,000,000,000 HX**, or **1000000000000000000000000000 minor units**, to the constructor's `msg.sender`. Decimals are 18, name is `HS XWesXkAAMSB0`, and symbol is `HX`.

There is no owner, subsequent mint, public burn, pause, blocklist, fee, transfer limit, initializer, or upgrade mechanism. Transfers move the exact requested amount and do not call the recipient. Transfers to the zero address revert. Zero-value transfers to valid addresses are supported. Failed operations revert atomically. The token does not receive ordinary ETH transfers or provide asset recovery.

Approvals follow standard ERC-20 behavior: `approve` replaces the allowance, `transferFrom` consumes finite allowances, and a maximum `uint256` allowance remains unchanged when spent. Users should approve only the amount needed; when replacing a nonzero allowance, revoke it first and wait for confirmation to reduce the standard approval replacement race. Approval changes emit `Approval`; allowance consumption does not emit another `Approval` in this OpenZeppelin version. Transfers and the initial mint emit `Transfer`.

## Deployment handoff

The network's **ProjectFactory must deploy the token** so it receives the entire supply. The token neither allocates supply itself nor grants its deploying factory any privileged role. The constructor has no arguments, dependencies, ETH value, or follow-up initialization calls. No application contracts are needed; the manifest's application `contracts` array should be empty.

The approved allocation, applied by the protocol factory, is:

| Destination | Total supply share | HX |
| --- | ---: | ---: |
| Launch pool paired with native ETH | 88% | 880,000,000 |
| Requester wallet | 2% | 20,000,000 |
| Accepted-work wallets, equally divided | 2% | 20,000,000 |
| Paired seats at admission, equally divided | 8% | 80,000,000 |

The 88% pool allocation is a percentage of the entire token supply. The token constructor must retain all of it at the factory until the factory performs the policy distribution. The local factory probe tests this accounting; it does not implement or verify the network factory, recipient eligibility, liquidity mechanics, or division/rounding among individual recipients.

Parameters for the separate manifest assignment:

| Parameter | Value |
| --- | --- |
| Kind / target | `evm_project` / Ethereum mainnet, chain ID `1` |
| Token artifact | `src/LaunchToken.sol:LaunchToken` |
| Token constructor arguments | `[]` |
| Token decimals / total supply | `18` / `1000000000000000000000000000` |
| Application contracts | `[]` |
| Pool pair currency | Native ETH, `0x0000000000000000000000000000000000000000` |
| Pool share of total supply | `88%` (`8800` basis points) |
| Admission fee field / tick spacing | `3000` / `60` |
| Legacy initialPrice field | `79228162514264337593543950336` |

The service's pinned policy determines the effective opening price. The manifest admission fee field is not the live trading fee. Per the supplied launch guidance, the factory reads trading fees from the network's LaunchFees contract: the default is 1.25% total, with 1% to the launch payer and 0.25% to IMD. Neither trading fees nor liquidity ownership are implemented by this token. The factory supplies the initialization guard and distributor; this contribution does not implement either.

The operator uses the network deployment service with the independently reviewed manifest and pinned policy. There is deliberately no direct `forge create` or broadcast script: direct deployment to an operator wallet would put the supply outside the required factory flow. No private key, RPC configuration, deployed address, or privileged wallet is embedded here. The final reviewer must check the accepted source, manifest arguments, mainnet target, ETH pairing, allocation, and policy together. Publication, signed-artifact linkage, admission, deployment, and explorer verification belong to the network services.

The later frontend must use the actual deployed addresses and exact poolKey from the service handoff, report truthful launch status, and fail closed outside chain ID 1. The motion identity and IPFS publication are outside this contract assignment.

## Offline build and validation

Foundry 1.8.3 and cached **solc 0.8.26** are required. All Solidity dependencies are ordinary files in `lib/`; no install, network, submodule, FFI, filesystem cheatcode permission, RPC, wallet, or environment configuration is needed. The compiler is version-pinned, optimization is enabled with 200 runs, EVM target is Paris, and `bytecode_hash = "none"` avoids metadata hash linkage in the deployed bytecode.

```sh
forge build --offline
forge test --offline
forge test --offline --fuzz-seed 0x20261007 --fuzz-runs 1024
forge fmt --check
```

The 23 tests include metadata and mint event checks, CREATE2 factory deployment, exact 88/2/2/8 distribution, transfers, finite and infinite allowances, zero values, invalid recipients, insufficient balances/allowances, failed-operation rollback, forbidden administrative selectors, recipient callback rejection, ETH rejection, runtime size/opcodes, and four bounded fuzz properties. Tests use no environment reads or writes, network forks, or precomputed CREATE addresses.

The ABI is in [`docs/abi/LaunchToken.json`](docs/abi/LaunchToken.json). Regenerate it with:

```sh
forge inspect src/LaunchToken.sol:LaunchToken abi --json > docs/abi/LaunchToken.json
```

See [`docs/abi/README.md`](docs/abi/README.md) for interface notes, [`lib/VENDORED.md`](lib/VENDORED.md) for dependencies, and [`REVIEW.md`](REVIEW.md) for the builder's checks and remaining independent review responsibilities. Local passing tests are not an independent audit.
