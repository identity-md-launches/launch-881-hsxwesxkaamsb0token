// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev Complements the accepted smoke tests with allowance isolation, replay,
/// rollback, and uint256 boundary properties. All inputs are bounded constructively.
/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    address internal constant OTHER_SPENDER = address(0x5EEE);
    LaunchToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new LaunchToken();
        assertTrue(token.transfer(ALICE, SUPPLY));
    }

    function test_oneWeiThenEntireRemainingBalance() public {
        vm.startPrank(ALICE);
        assertTrue(token.transfer(BOB, 1));
        assertTrue(token.transfer(BOB, SUPPLY - 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transfer(BOB, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsWithoutArithmeticPanic() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, SUPPLY, type(uint256).max)
        );
        vm.prank(ALICE);
        token.transfer(BOB, type(uint256).max);
        _assertUntouchedBalances();
    }

    function test_maximumDelegatedTransferCannotCreateTokens() public {
        _approve(ALICE, SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, SUPPLY, type(uint256).max)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, type(uint256).max);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        _assertUntouchedBalances();
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        _approve(ALICE, SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), SUPPLY - 1);
        assertEq(token.balanceOf(BOB), 1);
    }

    function test_delegatedSelfTransferSpendsAllowanceWithoutChangingBalance() public {
        _approve(ALICE, SPENDER, 42);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, ALICE, 42);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, ALICE, 42));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        _assertUntouchedBalances();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        _assertUntouchedBalances();
    }

    function test_ownerUsingTransferFromStillNeedsItsOwnAllowance() public {
        _approve(ALICE, SPENDER, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1);
        _approve(ALICE, ALICE, 1);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.allowance(ALICE, ALICE), 0);
        assertEq(token.allowance(ALICE, SPENDER), SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY - 1);
        assertEq(token.balanceOf(BOB), 1);
    }

    function test_approvalsAreIsolatedByBothOwnerAndSpender() public {
        vm.prank(ALICE);
        token.transfer(BOB, 100);
        _approve(ALICE, SPENDER, 7);
        _approve(ALICE, OTHER_SPENDER, 9);
        _approve(BOB, OTHER_SPENDER, 11);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(BOB, SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 7));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(ALICE, OTHER_SPENDER), 9);
        assertEq(token.allowance(BOB, OTHER_SPENDER), 11);
        assertEq(token.allowance(BOB, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY - 107);
        assertEq(token.balanceOf(BOB), 107);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_revokeInfiniteApprovalBlocksRepeatedSpendingUntilReapproved() public {
        _approve(ALICE, SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        _approve(ALICE, SPENDER, 0);
        for (uint256 i; i < 2; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
            vm.prank(SPENDER);
            token.transferFrom(ALICE, BOB, 1);
        }
        assertEq(token.balanceOf(ALICE), SUPPLY - 1);
        assertEq(token.balanceOf(BOB), 1);
        _approve(ALICE, SPENDER, 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 2));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY - 3);
        assertEq(token.balanceOf(BOB), 3);
    }

    function test_zeroDelegatedTransferEmitsEventAndPreservesInfiniteAllowance() public {
        _approve(ALICE, SPENDER, type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 0);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        _assertUntouchedBalances();
    }

    function test_ethAttachedToEachMutatorRevertsWithoutChanges() public {
        _approve(ALICE, SPENDER, 5);
        bytes[3] memory calls = [
            abi.encodeCall(token.transfer, (BOB, 1)),
            abi.encodeCall(token.approve, (SPENDER, 9)),
            abi.encodeCall(token.transferFrom, (ALICE, BOB, 1))
        ];
        vm.deal(ALICE, 1);
        vm.deal(SPENDER, 1);
        for (uint256 i; i < calls.length; ++i) {
            address caller = i == 2 ? SPENDER : ALICE;
            vm.prank(caller);
            (bool ok,) = address(token).call{value: 1}(calls[i]);
            assertFalse(ok, "ERC20 mutator accepted ETH");
            assertEq(caller.balance, 1);
        }
        assertEq(address(token).balance, 0);
        assertEq(token.allowance(ALICE, SPENDER), 5);
        _assertUntouchedBalances();
    }

    function testFuzz_roundTripRestoresBalancesWithoutTouchingApprovals(uint256 amountSeed, uint256 approved) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        _approve(ALICE, SPENDER, approved);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(BOB), amount);
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.allowance(ALICE, SPENDER), approved);
        _assertUntouchedBalances();
    }

    function testFuzz_repeatedApprovalIsIdempotentAndReplacementIsExact(uint256 first, uint256 second) public {
        _approve(ALICE, SPENDER, first);
        _approve(ALICE, SPENDER, first);
        assertEq(token.allowance(ALICE, SPENDER), first);
        _approve(ALICE, SPENDER, second);
        assertEq(token.allowance(ALICE, SPENDER), second);
        _assertUntouchedBalances();
    }

    function testFuzz_splitSpendingConsumesOnlyFiniteAllowance(uint256 approved, uint256 firstSeed, uint256 secondSeed)
        public
    {
        uint256 limit = approved < SUPPLY ? approved : SUPPLY;
        uint256 first = bound(firstSeed, 0, limit);
        uint256 second = bound(secondSeed, 0, limit - first);
        _approve(ALICE, SPENDER, approved);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, first));
        assertTrue(token.transferFrom(ALICE, SPENDER, second));
        vm.stopPrank();
        assertEq(token.allowance(ALICE, SPENDER), approved == type(uint256).max ? approved : approved - first - second);
        assertEq(token.balanceOf(ALICE), SUPPLY - first - second);
        assertEq(token.balanceOf(BOB), first);
        assertEq(token.balanceOf(SPENDER), second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedDelegatedOverdrawRollsBackFiniteAllowance(uint256 balanceSeed, uint256 extraSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = balance + bound(extraSeed, 1, type(uint256).max - 1 - balance);
        vm.prank(ALICE);
        token.transfer(BOB, SUPPLY - balance);
        _approve(ALICE, SPENDER, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferCannotBypassBalanceCheck(uint256 extraSeed) public {
        uint256 amount = SUPPLY + bound(extraSeed, 1, type(uint256).max - SUPPLY);
        _approve(ALICE, SPENDER, type(uint256).max);
        bytes memory failure =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, SUPPLY, amount);
        vm.expectRevert(failure);
        vm.prank(ALICE);
        token.transfer(ALICE, amount);
        vm.expectRevert(failure);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, amount);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        _assertUntouchedBalances();
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function _assertUntouchedBalances() internal view {
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
