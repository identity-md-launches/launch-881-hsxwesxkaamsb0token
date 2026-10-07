// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Local constructor/distribution probe, not a replacement for the protocol factory.
contract FactoryProbe {
    function deploy(bytes32 salt) external returns (LaunchToken) {
        return new LaunchToken{salt: salt}();
    }

    function distribute(LaunchToken token, address pool, address requester, address workers, address seats) external {
        require(token.transfer(pool, 880_000_000 ether));
        require(token.transfer(requester, 20_000_000 ether));
        require(token.transfer(workers, 20_000_000 ether));
        require(token.transfer(seats, 80_000_000 ether));
    }
}

contract RejectingReceiver {
    fallback() external payable {
        revert("no callbacks");
    }
}

contract LaunchTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    LaunchToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadataAndEntireSupply() public view {
        assertEq(token.name(), "HS XWesXkAAMSB0");
        assertEq(token.symbol(), "HX");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsSingleMint() public {
        vm.recordLogs();
        LaunchToken deployed = new LaunchToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_create2FactoryReceivesSupplyAndDistributesExactly() public {
        FactoryProbe factory = new FactoryProbe();
        LaunchToken deployed = factory.deploy(bytes32(uint256(1)));
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        address pool = address(0x1001);
        address requester = address(0x1002);
        address workers = address(0x1003);
        address seats = address(0x1004);
        factory.distribute(deployed, pool, requester, workers, seats);
        assertEq(deployed.balanceOf(pool), SUPPLY * 88 / 100);
        assertEq(deployed.balanceOf(requester), SUPPLY * 2 / 100);
        assertEq(deployed.balanceOf(workers), SUPPLY * 2 / 100);
        assertEq(deployed.balanceOf(seats), SUPPLY * 8 / 100);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupplyWithoutFee() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, SUPPLY);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAndSelfTransfers() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferDoesNotCallRecipient() public {
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 7 ether));
        assertEq(token.balanceOf(address(receiver)), 7 ether);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferInsufficientBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_approveEmitsAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 50));
        assertEq(token.allowance(address(this), SPENDER), 50);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 60));
        assertEq(token.allowance(address(this), SPENDER), 40);
        assertEq(token.balanceOf(ALICE), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 40));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(BOB), 40);
    }

    function test_transferFromWithoutApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromInsufficientBalancePreservesAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100);
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromInvalidRecipientPreservesAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromDoesNotNeedAllowanceButRejectsZeroSender() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        // OpenZeppelin rejects the zero allowance owner before reaching the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), BOB, 0);
    }

    function test_infiniteAllowanceIsUnchanged() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_noAdministrativeMintBurnOrUpgradeEntryPoints() public {
        string[18] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "owner()",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "setMinter(address)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "setFee(uint256)",
            "setBlacklist(address,bool)"
        ];
        address[2] memory callers = [address(this), ALICE];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < signatures.length; ++j) {
                vm.prank(callers[i]);
                (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[j], ALICE, uint256(1)));
                assertFalse(ok, signatures[j]);
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(address(this)), SUPPLY);
                assertEq(token.balanceOf(ALICE), 0);
            }
        }
    }

    function test_rejectsEther() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(ALICE.balance, 1 ether);
    }

    function test_runtimeHasNoEscapeOpcodesAndFitsSizeLimit() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedTransfer(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approved);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientAllowanceIsAtomic(uint256 rawAllowance, uint256 rawExtra) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = approved + bound(rawExtra, 1, SUPPLY - approved);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFuzz_transferSequenceConservesAllBalances(bytes32 seed) public {
        address[3] memory actors = [ALICE, BOB, SPENDER];
        token.transfer(ALICE, SUPPLY);
        for (uint256 i; i < 32; ++i) {
            seed = keccak256(abi.encode(seed, i));
            address from = actors[uint256(seed) % 3];
            address to = actors[(uint256(seed) >> 8) % 3];
            uint256 amount = bound(uint256(seed) >> 16, 0, token.balanceOf(from));
            vm.prank(from);
            assertTrue(token.transfer(to, amount));
            assertEq(token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(SPENDER), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }
}
