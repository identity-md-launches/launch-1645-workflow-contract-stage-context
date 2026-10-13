// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken internal token;
    address internal deployer = address(this);
    address internal alice = makeAddr("alice");

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadata() public view {
        assertEq(token.name(), "VisualIdentity.md");
        assertEq(token.symbol(), "VIMD");
        assertEq(token.decimals(), 18);
    }

    function test_mintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.balanceOf(deployer), token.totalSupply());
    }

    function test_transferMovesExactAmount() public {
        uint256 amount = 1234e18;
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), 10 ** 27 - amount);
        assertEq(token.totalSupply(), 10 ** 27);
    }

    function test_transferBeyondBalanceReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(deployer, 1);
    }

    function test_noMintFunction() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1));
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
        assertEq(token.totalSupply(), 10 ** 27);
    }

    function testFuzz_transferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, 10 ** 27);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice) + token.balanceOf(deployer), 10 ** 27);
    }
}
