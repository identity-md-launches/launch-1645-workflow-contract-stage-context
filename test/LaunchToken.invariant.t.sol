// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @notice Random transfers, approvals and transferFroms among a fixed set of holders, including
///         amounts above the balance or allowance, which must revert and move nothing.
contract LaunchTokenHandler is CommonBase, StdCheats, StdUtils {
    LaunchToken public immutable token;
    address[] public holders;

    uint256 public transfersSucceeded;
    uint256 public transfersRejected;
    uint256 public transferFromsSucceeded;
    uint256 public transferFromsRejected;

    constructor(LaunchToken token_, address[] memory holders_) {
        token = token_;
        holders = holders_;
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function _holder(uint256 seed) internal view returns (address) {
        return holders[bound(seed, 0, holders.length - 1)];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _holder(fromSeed);
        address to = _holder(toSeed);
        uint256 fromBalance = token.balanceOf(from);
        // Up to one unit over the balance so the insufficient-balance path is reached.
        amount = bound(amount, 0, fromBalance + 1);
        uint256 toBalance = token.balanceOf(to);
        bool shouldSucceed = amount <= fromBalance;

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            require(ok, "handler: transfer returned false");
            require(shouldSucceed, "handler: transfer beyond balance succeeded");
            if (from != to) {
                require(token.balanceOf(from) == fromBalance - amount, "handler: sender delta");
                require(token.balanceOf(to) == toBalance + amount, "handler: recipient delta");
            } else {
                require(token.balanceOf(from) == fromBalance, "handler: self transfer changed balance");
            }
            transfersSucceeded += 1;
        } catch {
            require(!shouldSucceed, "handler: transfer within balance reverted");
            require(token.balanceOf(from) == fromBalance && token.balanceOf(to) == toBalance, "handler: failed move");
            transfersRejected += 1;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _holder(ownerSeed);
        address spender = _holder(spenderSeed);
        vm.prank(owner);
        token.approve(spender, amount);
        require(token.allowance(owner, spender) == amount, "handler: allowance not set");
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _holder(spenderSeed);
        address from = _holder(fromSeed);
        address to = _holder(toSeed);
        uint256 fromBalance = token.balanceOf(from);
        uint256 allowance = token.allowance(from, spender);
        amount = bound(amount, 0, fromBalance + 1);
        uint256 toBalance = token.balanceOf(to);
        bool shouldSucceed = amount <= fromBalance && amount <= allowance;

        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            require(ok, "handler: transferFrom returned false");
            require(shouldSucceed, "handler: transferFrom beyond balance or allowance succeeded");
            if (allowance != type(uint256).max) {
                require(token.allowance(from, spender) == allowance - amount, "handler: allowance delta");
            } else {
                require(token.allowance(from, spender) == type(uint256).max, "handler: infinite allowance reduced");
            }
            if (from != to) {
                require(token.balanceOf(from) == fromBalance - amount, "handler: sender delta");
                require(token.balanceOf(to) == toBalance + amount, "handler: recipient delta");
            }
            transferFromsSucceeded += 1;
        } catch {
            require(!shouldSucceed, "handler: permitted transferFrom reverted");
            require(token.balanceOf(from) == fromBalance && token.balanceOf(to) == toBalance, "handler: failed move");
            require(token.allowance(from, spender) == allowance, "handler: failed transferFrom changed allowance");
            transferFromsRejected += 1;
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 50
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 10 ** 27;

    LaunchToken internal token;
    LaunchTokenHandler internal handler;
    address[] internal holders;

    function setUp() public {
        token = new LaunchToken();
        for (uint256 i; i < 5; ++i) {
            holders.push(makeAddr(string.concat("holder", vm.toString(i))));
        }
        // Uneven starting balances; one holder starts empty. The test keeps the remainder.
        token.transfer(holders[0], 400_000_000e18);
        token.transfer(holders[1], 1);
        token.transfer(holders[2], 123_456_789e18);
        token.transfer(holders[3], 50_000e18);
        handler = new LaunchTokenHandler(token, holders);
        targetContract(address(handler));
    }

    /// @notice The supply is fixed at launch and nothing can change it.
    function invariant_supplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
        assertEq(token.decimals(), 18);
    }

    /// @notice Every unit is held by someone: holder balances plus the test's remainder equal the supply.
    function invariant_balancesSumToSupply() public view {
        uint256 sum = token.balanceOf(address(this)) + token.balanceOf(address(handler));
        for (uint256 i; i < holders.length; ++i) {
            uint256 b = token.balanceOf(holders[i]);
            assertLe(b, SUPPLY, "a balance exceeds the supply");
            sum += b;
        }
        assertEq(sum, SUPPLY, "balances do not sum to the supply");
        assertEq(token.balanceOf(address(handler)), 0, "the handler never holds tokens");
    }
}
