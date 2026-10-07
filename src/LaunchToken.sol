// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title HS XWesXkAAMSB0 (HX)
/// @notice Fixed-supply launch token; all distribution is performed by ProjectFactory.
/// @dev The constructor's caller receives the entire supply. There are no privileged roles.
contract LaunchToken is ERC20 {
    constructor() ERC20("HS XWesXkAAMSB0", "HX") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
