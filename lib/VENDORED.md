# Vendored dependencies

Copied as ordinary source files from the preinstalled `/home/seat5/vendor` mirrors. No submodules, package installation, remote imports, compiler binaries, or dependency repository metadata are included.

- **OpenZeppelin Contracts:** mirror package version `5.7.0`. Included only `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `IERC6093.sol`, and the MIT license. The ERC20 source identifies its last update as v5.5.0; the mirror package version is not a claim that every source file changed in that version. These files are unmodified.
- **forge-std:** mirror package version `1.16.2`. Included its `src/` directory and MIT/Apache-2.0 licenses, unmodified. This library is used only by tests.

`SHA256SUMS` records the exact vendored file contents. From the repository root, verify with `sha256sum -c lib/SHA256SUMS`. The hashes identify these delivered bytes independently of a moving upstream branch; mirror git metadata was not read or copied.
