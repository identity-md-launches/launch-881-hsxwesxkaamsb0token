# LaunchToken ABI

`LaunchToken.json` is the compiler-exported JSON ABI for `src/LaunchToken.sol:LaunchToken` using the repository's pinned Solidity 0.8.26 configuration. Constructor inputs are empty and state mutability is nonpayable.

| Call | Behavior |
| --- | --- |
| `name()` | `HS XWesXkAAMSB0` |
| `symbol()` | `HX` |
| `decimals()` | `18` |
| `totalSupply()` | Always `1000000000000000000000000000` |
| `balanceOf(address)` | Balance in minor units |
| `allowance(address,address)` | Remaining spending authorization in minor units |
| `approve(address,uint256)` | Replace caller's allowance for a nonzero spender; returns `true` |
| `transfer(address,uint256)` | Move caller's tokens to a nonzero recipient; returns `true` |
| `transferFrom(address,address,uint256)` | Move tokens using caller's allowance; returns `true` |

Events are standard `Transfer(address indexed from,address indexed to,uint256 value)` and `Approval(address indexed owner,address indexed spender,uint256 value)`. Reverts use OpenZeppelin's ERC-6093 custom errors, listed in the ABI. An error's presence in the ABI is not a guarantee that every error is reachable through this token's public functions.

All token amounts use 18 decimals. The ABI contains no owner, mint, burn, fee, pause, blocklist, or upgrade entry point. This ABI documents the token only; obtain factory and pool interfaces and actual deployment addresses from the verified network handoff.
