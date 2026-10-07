// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev Closed set of four holders plus the token itself as a donation recipient.
/// Ghost flows come from requested successful operations, never from balanceOf.
/// No storage writes, token deal, forks, or environment mutation are used.
contract LaunchTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    LaunchToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public positiveTransfers;
    uint256 public positiveDelegatedTransfers;
    uint256 public rejectedCalls;

    constructor() {
        token = new LaunchToken();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = address(uint160(0x1000 + i));
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
            received[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 amount = _amount(amountSeed, _balance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
        if (amount > 0) ++positiveTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        uint256 amount;
        if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = type(uint256).max - 1;
        else if (mode % 4 == 3) amount = amountSeed;
        // mode 0 revokes an allowance, including an existing infinite allowance.
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _recipient(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = _balance(owner);
        uint256 amount = _amount(amountSeed, balance < allowed ? balance : allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        _recordTransfer(owner, to, amount);
        if (amount > 0) ++positiveDelegatedTransfers;
    }

    function rejectOverdraw(uint256 ownerSeed, uint256 spenderSeed, uint256 extraSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address recipient = _actor((ownerSeed % 4 + 1) % 4);
        uint256 balance = _balance(owner);
        uint256 amount = balance + bound(extraSeed, 1, type(uint256).max - balance);
        if (delegated) _approve(owner, spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, recipient, amount);
        else token.transfer(recipient, amount);
        ++rejectedCalls;
    }

    function rejectOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 approved = bound(amountSeed, 0, SUPPLY - 1);
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, _recipient(ownerSeed), approved + 1);
        ++rejectedCalls;
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, _balance(owner));
        if (mode % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (mode % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amountSeed);
        } else {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
        ++rejectedCalls;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _recipient(uint256 seed) internal view returns (address) {
        uint256 index = bound(seed, 0, actors.length);
        return index == actors.length ? address(token) : actors[index];
    }

    function _balance(address actor) internal view returns (uint256) {
        return received[actor] - sent[actor];
    }

    function _amount(uint256 seed, uint256 limit) internal pure returns (uint256) {
        // Exercise zero, one wei, the full available balance/allowance, and partial amounts.
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return limit == 0 ? 0 : 1;
        if (seed % 4 == 2) return limit;
        return bound(seed, 0, limit);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }
}

/// @dev Every handler call must complete, including its assertions and expected reverts.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    LaunchTokenHandler internal handler;
    LaunchToken internal token;

    function setUp() public {
        handler = new LaunchTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectOverdraw.selector;
        selectors[4] = handler.rejectOverspend.selector;
        selectors[5] = handler.rejectZeroAddress.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev Workflow: exactly 1 billion HX, no mint/burn or transfer tax.
    function invariant_fixedSupplyEqualsAllHeldTokens() public view {
        uint256 held = token.balanceOf(address(token));
        for (uint256 i; i < 4; ++i) {
            held += token.balanceOf(handler.actors(i));
        }
        assertEq(held, SUPPLY, "tokens were created, destroyed, or diverted");
        assertEq(token.totalSupply(), SUPPLY, "fixed supply changed");
        assertEq(token.balanceOf(address(handler)), 0, "deployer retained or recovered tokens");
        assertEq(token.balanceOf(address(0)), 0, "tokens were burned");
    }

    /// @dev Initial allocation + inflows = current holdings + outflows, per account.
    function invariant_eachHolderMatchesAuthorizedFlows() public view {
        for (uint256 i; i < 5; ++i) {
            address holder = i == 4 ? address(token) : handler.actors(i);
            assertEq(
                token.balanceOf(holder) + handler.sent(holder), handler.received(holder), "incorrect holder accounting"
            );
        }
    }

    /// @dev Only that owner's approvals and successful spends may change a pair's allowance.
    function invariant_allowancesMatchIndependentHistory() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
            assertEq(token.allowance(owner, address(0)), 0);
        }
    }

    /// @dev Deterministic witness that the harness reaches positive delegated transfers,
    /// revocation, full-balance self-transfers, donations, and every rejection branch.
    function test_handlerReachesTransfersAndFailureBranches() public {
        handler.transfer(0, 1, 1);
        handler.approve(1, 2, 20, 3);
        handler.transferFrom(1, 2, 3, 2);
        handler.approve(0, 0, 0, 1);
        handler.transferFrom(0, 0, 0, 2);
        handler.approve(0, 0, 0, 0);
        handler.transfer(2, 4, 1);
        handler.rejectOverdraw(0, 1, 1, false);
        handler.rejectOverdraw(1, 2, type(uint256).max, true);
        handler.rejectOverspend(2, 3, 0);
        handler.rejectZeroAddress(0, 1, 0, 0);
        handler.rejectZeroAddress(1, 2, type(uint256).max, 1);
        handler.rejectZeroAddress(2, 3, 1, 2);
        assertEq(handler.positiveTransfers(), 2);
        assertEq(handler.positiveDelegatedTransfers(), 2);
        assertEq(handler.rejectedCalls(), 6);
        invariant_fixedSupplyEqualsAllHeldTokens();
        invariant_eachHolderMatchesAuthorizedFlows();
        invariant_allowancesMatchIndependentHistory();
    }
}
